-- =====================================================================
--  SCHEMA « kredi » — 5 : ce dont l'application HTML a besoin
--  (vues « externes », automatisation DS, comptes utilisateurs)
-- =====================================================================

drop view if exists kredi.v_formulaires;

-- 1. Ajustements de colonnes : les champs « Données … » sont du texte JSON dans le HTML
alter table kredi.formulaires
  alter column documents_detail type text using documents_detail::text,
  alter column donnees_lettres  type text using donnees_lettres::text,
  alter column donnees_finance  type text using donnees_finance::text,
  alter column donnees_contrat  type text using donnees_contrat::text,
  add column if not exists id_contrat uuid references kredi.contrats(id) on delete set null;
alter table kredi.rapports_cloture alter column donnees_rapport type text using donnees_rapport::text;
alter table kredi.parametres add column if not exists id uuid not null default gen_random_uuid() unique;
alter table kredi.dossiers_clients add column if not exists nom_formulaire text, add column if not exists zone_formulaire text, add column if not exists lieu_formulaire text;

-- la vue v_formulaires doit voir id_contrat : on la recrée (f.* l'inclut)
create view kredi.v_formulaires with (security_invoker = true) as
with b as (
  select f.*,
    trim(coalesce(f.nom,'')) || ' ' || trim(coalesce(f.prenom,'')) as nom_complet,
    'FC-' || right(coalesce(f.numero_epargne,''), 6) as id_formulaire,
    kredi.ajout_jours_ouvrables(f.date_remise,   case when f.type_demande = 'Renouvellement' then 1 else 2 end) as date_retour_attendue,
    kredi.ajout_jours_ouvrables(f.date_debut_am, case when f.type_demande = 'Renouvellement' then 2 else 3 end) as deadline_am,
    kredi.ajout_jours_ouvrables(f.date_envoi_manager, 2) as deadline_manager
  from kredi.formulaires f)
select b.*,
  case b.etape
    when '1 - Formulaire remis à l''agent' then case when b.date_retour_attendue < current_date then 'Retard agent' else 'Attente agent' end
    when '2 - Retourné au secrétariat' then 'A prendre par AM'
    when '3 - En analyse (AM)' then case when b.deadline_am < current_date then 'Retard AM' else 'Analyse AM' end
    when '4 - En validation (Manager)' then case when b.deadline_manager < current_date then 'Retard Manager' else 'Validation Manager' end
    when '5 - Clôturé' then 'Clôturé' end as statut_delai,
  case
    when b.etape = '5 - Clôturé' then 'Clôturé'
    when coalesce(b.motif_blocage,'') <> '' then 'Bloqué'
    when b.etape = '1 - Formulaire remis à l''agent' then
      case when b.date_retour_attendue is null then 'En cours'
           when b.date_retour_attendue = current_date then 'À remettre aujourd''hui'
           when b.date_retour_attendue < current_date then 'En retard' else 'En cours' end
    when coalesce(b.nom,'') = '' or coalesce(b.prenom,'') = '' or coalesce(b.numero_epargne,'') = '' or cardinality(b.documents_recus) = 0 then 'À compléter'
    when b.date_retour > b.date_retour_attendue then 'Remis en retard'
    else 'Remis à temps' end as statut_suivi,
  case b.etape
    when '2 - Retourné au secrétariat' then case when b.date_retour is not null and current_date - b.date_retour > 1 then 'AM · À prendre (en attente)' else 'AM · À prendre' end
    when '3 - En analyse (AM)' then
      case when coalesce(b.motif_blocage,'') <> '' then 'AM · Bloqué'
           when b.decision_am = 'Ajourné' then 'AM · Ajourné (à compléter)'
           when b.deadline_am is null then 'AM · En analyse'
           when b.deadline_am < current_date then 'AM · En retard'
           when b.deadline_am = current_date then 'AM · À finaliser aujourd''hui'
           else 'AM · En analyse' end
    when '4 - En validation (Manager)' then 'AM · Validé → Manager'
    when '5 - Clôturé' then case when b.decision_am = 'Non validé' then 'AM · Non validé' else 'AM · Terminé' end
  end as statut_am,
  nullif(concat_ws(' | ',
    case when b.date_retour is not null then 'Agent:' || case when b.date_retour > b.date_retour_attendue then 'KO' else 'OK' end end,
    case when b.date_decision_am is not null then 'AM:' || case when b.date_decision_am > b.deadline_am then 'KO' else 'OK' end end,
    case when b.date_decision_manager is not null then 'Mgr:' || case when b.date_decision_manager > b.deadline_manager then 'KO' else 'OK' end end), '') as respect_delais,
  kredi.jours_ouvrables_entre(b.date_remise, coalesce(b.date_retour, current_date)) as jours_utilises,
  greatest(0, coalesce(kredi.jours_ouvrables_entre(b.date_retour_attendue, coalesce(b.date_retour, current_date)),0)) as retard_jours,
  kredi.jours_ouvrables_entre(b.date_debut_am, coalesce(b.date_decision_am, current_date)) as jours_am_utilises,
  case when b.deadline_am < coalesce(b.date_decision_am, current_date) then coalesce(b.date_decision_am, current_date) - b.deadline_am else 0 end as retard_am_jours,
  kredi.nb_etapes_ok(b.id) as conformite_ok,
  round(kredi.nb_etapes_ok(b.id) * 100.0 / kredi.nb_etapes_actives()) as conformite_pct,
  (select s.score_total from kredi.scorings s where s.id_formulaire = b.id) as score_credit,
  case when coalesce(b.montant_accorde, b.montant_demande) is not null and b.taux_fonds_garantie is not null
       then round(coalesce(b.montant_accorde, b.montant_demande) * b.taux_fonds_garantie / 100) end as montant_fdg_requis,
  case when b.montant_accorde is not null
       then round(b.montant_accorde * (1 + coalesce(b.taux_interet,0) / 100 * coalesce(nullif(b.duree_mois,0),1))) end as montant_total_am,
  (select d.num_ds from kredi.dossiers_clients d where d.id = b.id_dossier_client) as num_ds
from b;

-- 2. Fiche de validation au format de l'app (clé « FC-XX-00001#04 »)
create or replace view kredi.v_validations with (security_invoker = true) as
select v.*, e.libelle as etape, f.numero_dossier || '#' || lpad(v.num_etape::text, 2, '0') as cle
from kredi.validations v
join kredi.etapes_validation e on e.num = v.num_etape
join kredi.formulaires f on f.id = v.id_formulaire;

-- 3. Dossier client : formulaires et crédits rattachés, statut
create or replace view kredi.v_dossiers_clients with (security_invoker = true) as
select d.*,
  coalesce((select array_agg(f.id order by f.created_at) from kredi.formulaires f where f.id_dossier_client = d.id), '{}') as formulaires,
  coalesce((select array_agg(c.id_compte_credit) from kredi.contrats c where c.id_dossier_client = d.id and c.id_compte_credit is not null), '{}') as credits,
  case when exists (select 1 from kredi.formulaires f where f.id_dossier_client = d.id and f.etape <> '5 - Clôturé') then 'Demande en cours'
       when exists (select 1 from kredi.formulaires f where f.id_dossier_client = d.id and f.decision_manager = 'Approuvé') then 'Client crédit'
       else 'Prospect' end as statut_dossier
from kredi.dossiers_clients d;

-- 4. Vues « externes » : comptes épargne, fonds de garantie, comptes crédit, transactions
--    (lecture seule, réservées aux utilisateurs actifs de l'application crédit)
create or replace view kredi.ext_comptes_epargne as
select ce.id_compte_epargne as id, ce.created_at,
  upper(ce.no_compte) as no_compte, p.nom, p.prenom, trim(coalesce(p.nom,'') || ' ' || coalesce(p.prenom,'')) as nom_complet,
  p.pseudo, p.numero_telephone as telephone, p.adresse, p.lieu_de_travail, p.occupation, p.activite,
  p.sexe, p.date_naissance, p.nif_cin, p.secteur as zone,
  ce.solde_actuel as solde, ce.fonds_garantie, op.montant as plan_journalier,
  coalesce(pr.firstname || ' ' || pr.name, '') as collecteur,
  ce.categorie_compte_epargne as categorie, ce.type_compte_epargne as type_compte,
  case when ce.categorie_compte_epargne = 'Grandon' then 'Grandon' else 'Epargne' end as programme,
  ce.date_creation, false as bloque, ce.id_personne
from public.comptes_epargne ce
left join public.personnes p on p.id_personne = ce.id_personne
left join public.offres_plans op on op.id_plan = ce.id_plan
left join public.profiles pr on pr.user_id = ce.created_by
where kredi.est_utilisateur_actif();

create or replace view kredi.ext_comptes_credit as
select cc.id_compte_credit as id, cc.created_at, upper(cc.no_compte) as id_credit,
  trim(coalesce(p.nom,'') || ' ' || coalesce(p.prenom,'')) as nom_complet, p.adresse as adresse_entreprise,
  upper(ce.no_compte) as numero_epargne, cc.type_compte_credit as type_credit,
  cc.montant_prete as montant_pret, cc.taux_interet, cc.duree_credit_mois, cc.paiement_journalier,
  cc.montant_final, cc.date_debut, cc.date_fin, cc.montant_restant as restant,
  coalesce(cc.paiement_cumule,0) as remboursement,
  (select count(*) from public.transactions_credit t where t.id_compte_credit = cc.id_compte_credit) as nb_versements,
  (select max(t.date_transaction) from public.transactions_credit t where t.id_compte_credit = cc.id_compte_credit) as dernier_versement,
  case when coalesce(cc.montant_restant,0) <= 0 then 'Soldé' when cc.date_fin < now() then 'En retard' else 'En cours' end as statut_creances,
  coalesce((select array_agg(c.id_dossier_client) from kredi.contrats c where c.id_compte_credit = cc.id_compte_credit and c.id_dossier_client is not null), '{}') as dossiers_clients
from public.comptes_credit cc
left join public.personnes p on p.id_personne = cc.id_personne
left join public.comptes_epargne ce on ce.id_compte_epargne = cc.id_compte_epargne
where kredi.est_utilisateur_actif();

create or replace view kredi.ext_transactions_epargne as
select t.id_transaction_epargne as id, t.created_at, t.date_transaction::date as date, to_char(t.date_transaction, 'YYYY-MM') as mois,
  upper(t.no_compte) as compte, coalesce(pr.firstname || ' ' || pr.name, '') as collecteur,
  case when upper(left(t.type_transaction,1)) = 'D' then t.montant else 0 end as depot,   -- D = dépôt
  case when upper(left(t.type_transaction,1)) = 'R' then t.montant else 0 end as retrait  -- R = retrait
from public.transactions_epargne t
left join public.profiles pr on pr.user_id = t.created_by
where kredi.est_utilisateur_actif();

create or replace view kredi.ext_mois_transactions as
select distinct to_char(date_transaction, 'YYYY-MM') as mois from public.transactions_epargne
where kredi.est_utilisateur_actif() and date_transaction is not null;

grant select on kredi.v_formulaires, kredi.v_validations, kredi.v_dossiers_clients, kredi.ext_comptes_epargne, kredi.ext_comptes_credit,
  kredi.ext_transactions_epargne, kredi.ext_mois_transactions to authenticated;

-- 5. Automatisation « Dossier client » (remplace l'automatisation Airtable) :
--    à la création d'un formulaire sans DS rattaché, un nouveau DS est créé.
create or replace function kredi.formulaire_apres_insert()
returns trigger language plpgsql security definer set search_path = kredi, public as $$
declare ds uuid; ctrl text;
begin
  perform set_config('kredi.systeme','on',true);
  insert into kredi.validations (id_formulaire, num_etape, statut, verifie_par, date_verification)
  select new.id, e.num,
         case when e.num = 1 then 'Conforme'
              when e.renouvellement_seulement and coalesce(new.type_demande,'') <> 'Renouvellement' then 'Non applicable'
              else 'À faire' end,
         case when e.num = 1 or (e.renouvellement_seulement and coalesce(new.type_demande,'') <> 'Renouvellement') then 'Système' end,
         case when e.num = 1 or (e.renouvellement_seulement and coalesce(new.type_demande,'') <> 'Renouvellement') then current_date end
  from kredi.etapes_validation e where e.actif;

  if new.etape <> '5 - Clôturé' and coalesce(trim(new.nom),'') <> '' then
    if new.id_dossier_client is null then
      if new.type_demande is null then ctrl := 'À vérifier - type manquant';
      elsif coalesce(new.numero_epargne,'') = '' then ctrl := 'À vérifier - compte épargne manquant';
      else
        insert into kredi.dossiers_clients (nom, zone, lieu_travail, id_personne, nom_formulaire, zone_formulaire, lieu_formulaire)
        values (trim(new.nom) || ' ' || trim(coalesce(new.prenom,'')), new.zone, new.lieu_travail, new.id_personne,
                trim(new.nom) || ' ' || trim(coalesce(new.prenom,'')), new.zone, new.lieu_travail)
        returning id into ds;
        ctrl := 'OK - DS créé';
      end if;
    else
      ctrl := case when new.type_demande = 'Renouvellement' then 'OK - Renouvellement' else 'OK - DS trouvé par système' end;
    end if;
    update kredi.formulaires set id_dossier_client = coalesce(ds, id_dossier_client), controle_ds = coalesce(controle_ds, ctrl) where id = new.id;
  end if;
  perform set_config('kredi.systeme','',true);
  return null;
end $$;

-- 6. Comptes utilisateurs (Supabase Auth) — gérés par l'Admin depuis l'application
create or replace function kredi.email_de(p_identifiant text)
returns text language sql immutable set search_path = '' as $$
  select case when position('@' in p_identifiant) > 0 then lower(p_identifiant) else lower(p_identifiant) || '@kredi.bwatsekrem.ht' end
$$;

create or replace function kredi.admin_creer_utilisateur(p_identifiant text, p_nom text, p_role text, p_equipe_am text, p_mdp text)
returns uuid language plpgsql security definer set search_path = kredi, public, extensions as $$
declare uid uuid := gen_random_uuid(); em text := kredi.email_de(p_identifiant);
begin
  if not kredi.contourne_regles() then raise exception 'Réservé à l''Admin' using errcode = 'P0001'; end if;
  if length(coalesce(p_mdp,'')) < 6 then raise exception 'Mot de passe trop court (≥ 6)' using errcode = 'P0001'; end if;
  if exists (select 1 from kredi.utilisateurs where lower(identifiant) = lower(p_identifiant)) then
    raise exception 'Cet identifiant existe déjà' using errcode = 'P0001'; end if;
  select id into uid from auth.users where email = em;
  if uid is null then
    uid := gen_random_uuid();
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, email_change, email_change_token_new, recovery_token)
    values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', em, crypt(p_mdp, gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}', jsonb_build_object('nom', p_nom), now(), now(), '', '', '', '');
    insert into auth.identities (id, user_id, provider_id, identity_data, provider, created_at, updated_at, last_sign_in_at)
    values (gen_random_uuid(), uid, uid::text, jsonb_build_object('sub', uid::text, 'email', em, 'email_verified', true), 'email', now(), now(), now());
  else
    update auth.users set encrypted_password = crypt(p_mdp, gen_salt('bf')), updated_at = now() where id = uid;
  end if;
  insert into kredi.utilisateurs (user_id, identifiant, nom_complet, role, equipe_am, actif, doit_changer_mdp)
  values (uid, lower(p_identifiant), coalesce(nullif(p_nom,''), p_identifiant), p_role, nullif(p_equipe_am,''), true, true);
  return uid;
end $$;

create or replace function kredi.admin_reinit_mdp(p_user uuid, p_mdp text)
returns void language plpgsql security definer set search_path = kredi, public, extensions as $$
begin
  if not kredi.contourne_regles() then raise exception 'Réservé à l''Admin' using errcode = 'P0001'; end if;
  if length(coalesce(p_mdp,'')) < 6 then raise exception 'Mot de passe trop court (≥ 6)' using errcode = 'P0001'; end if;
  update auth.users set encrypted_password = crypt(p_mdp, gen_salt('bf')), updated_at = now() where id = p_user;
  perform set_config('kredi.systeme','on',true);
  update kredi.utilisateurs set doit_changer_mdp = true where user_id = p_user;
  perform set_config('kredi.systeme','',true);
end $$;

-- vérifie le mot de passe d'un Admin actif (autorisation exceptionnelle d'un RDV) → nom de l'Admin ou null
create or replace function kredi.verifier_mdp_admin(p_mdp text)
returns text language sql stable security definer set search_path = kredi, public, extensions as $$
  select u.nom_complet from kredi.utilisateurs u join auth.users a on a.id = u.user_id
  where kredi.est_utilisateur_actif() and u.role = 'Admin' and u.actif and a.encrypted_password = crypt(p_mdp, a.encrypted_password)
  limit 1
$$;

-- vérifie le mot de passe actuel de l'utilisateur connecté (changement de mot de passe)
create or replace function kredi.verifier_mon_mdp(p_mdp text)
returns boolean language sql stable security definer set search_path = kredi, public, extensions as $$
  select exists (select 1 from auth.users a where a.id = auth.uid() and a.encrypted_password = crypt(p_mdp, a.encrypted_password))
$$;

-- fin du changement de mot de passe : lève le drapeau « mot de passe temporaire » et note la connexion
create or replace function kredi.marquer_connexion(p_mdp_change boolean default false)
returns void language plpgsql security definer set search_path = kredi, public as $$
begin
  perform set_config('kredi.systeme','on',true);
  update kredi.utilisateurs set derniere_connexion = now(),
         doit_changer_mdp = case when p_mdp_change then false else doit_changer_mdp end
  where user_id = auth.uid();
  perform set_config('kredi.systeme','',true);
end $$;

revoke execute on function kredi.admin_creer_utilisateur(text,text,text,text,text), kredi.admin_reinit_mdp(uuid,text),
  kredi.verifier_mdp_admin(text), kredi.verifier_mon_mdp(text), kredi.marquer_connexion(boolean), kredi.email_de(text) from public, anon;
grant execute on function kredi.admin_creer_utilisateur(text,text,text,text,text), kredi.admin_reinit_mdp(uuid,text),
  kredi.verifier_mdp_admin(text), kredi.verifier_mon_mdp(text), kredi.marquer_connexion(boolean), kredi.email_de(text) to authenticated;
