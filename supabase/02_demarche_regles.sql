-- =====================================================================
--  SCHEMA « kredi » — 2/3 : référentiel de la démarche + règles métier
--  Les règles ci-dessous reprennent celles du HTML v1.52.1, mais côté base :
--  elles s'appliquent même si quelqu'un écrit directement dans Supabase.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Référentiel : phases, étapes de validation, étapes du dossier
-- ---------------------------------------------------------------------
insert into kredi.phases (num, titre, description, porte_etape) values
 (1,'Phase 1 — Suivi du formulaire','Formulaire, régularité du compte épargne, (renouvellement) rapport de clôture et attestation, analyse quantitative et qualitative. La validation du suivi (étape 04) ouvre la phase 2.',4),
 (2,'Phase 2 — Détection et gestion du risque','Visite du commerce, analyse financière approfondie, visite du domicile, témoin, confirmation des téléphones. Le rapport de risques (étape 07) ouvre la phase 3.',7),
 (3,'Phase 3 — Décision','Grille de scoring, documents administratifs et de garantie, synthèse et approbation AM avec les conditions du crédit.',null);

insert into kredi.etapes_validation (num, libelle, description, phase, ordre, est_porte, automatique, renouvellement_seulement, actif) values
 (1, '01 - Formulaire de demande présent','Vérifié automatiquement : le formulaire FC- existe.',1,1,false,true,false,true),
 (16,'16 - Rapport de régularité du compte épargne','Enregistré manuellement par l''AM après lecture du rapport de régularité.',1,2,false,false,false,true),
 (17,'17 - Rapport de clôture du crédit précédent (renouvellement)','Automatique : rapport RC- rempli par le recouvrement et vérifié Conforme par l''AM. Nouveau crédit → Non applicable.',1,3,false,true,true,true),
 (18,'18 - Attestation de remboursement complet du crédit précédent (renouvellement)','Automatique : attestation de remboursement complet (solde 0) dans le rapport de clôture. Nouveau crédit → Non applicable.',1,4,false,true,true,true),
 (3, '03 - Analyse quantitative','Ventes, marges, charges, capacité de remboursement.',1,5,false,false,false,true),
 (2, '02 - Analyse qualitative du client','Clientèle, réputation, position, responsabilité familiale, discipline d''épargne.',1,6,false,false,false,true),
 (4, '04 - Validation du suivi du formulaire','PORTE phase 1 : l''AM confirme que le formulaire répond aux critères. Ouvre la phase 2.',1,7,true,false,false,true),
 (5, '05 - Visite du commerce du client','Visite par l''AM ; local et activité confirmés.',2,1,false,false,false,true),
 (6, '06 - Analyse financière approfondie','Analyse financière détaillée par l''AM.',2,2,false,false,false,true),
 (12,'12 - Visite du domicile du client','Domicile visité ; exposition aux risques évaluée.',2,3,false,false,false,true),
 (9, '09 - Information et pièce d''identité du témoin','Nom, adresse, téléphone et pièce du témoin vérifiés.',2,4,false,false,false,true),
 (19,'19 - Confirmation du numéro de téléphone du client','Appel du client au numéro déclaré.',2,5,false,false,false,true),
 (20,'20 - Confirmation du numéro de téléphone du témoin','Appel du témoin au numéro indiqué.',2,6,false,false,false,true),
 (7, '07 - Détection et gestion du risque','PORTE phase 2 — automatique : rapport de risques enregistré (niveau global + synthèse). Ouvre la phase 3.',2,7,true,true,false,true),
 (15,'15 - Grille de scoring réalisée','Automatique : grille de scoring /100 enregistrée.',3,1,false,true,false,true),
 (8, '08 - Documents administratifs et de garantie reçus','Bail, fiche de transaction, contrat de propriété…',3,2,false,false,false,true),
 (13,'13 - Synthèse, recommandation et approbation AM','Conditions du crédit (montant, durée, taux, paiement/jour, FDG) puis approbation AM.',3,3,false,false,false,true),
 (10,'10 - Encaissement des frais de dossier confirmé','Retirée : suivie par la page Finance.',null,null,false,false,false,false),
 (11,'11 - Fonds de garantie prélevé confirmé','Retirée : suivie par la page Finance.',null,null,false,false,false,false),
 (14,'14 - Lettre de validation au client rédigée','Retirée : gérée par le secrétariat (Correspondance).',null,null,false,false,false,false);

insert into kredi.etapes_dossier (num, libelle) values
 (1,'1 - Formulaire remis à l''agent'),
 (2,'2 - Retourné au secrétariat'),
 (3,'3 - En analyse (AM)'),
 (4,'4 - En validation (Manager)'),
 (5,'5 - Clôturé');

alter table kredi.formulaires add constraint formulaires_etape_fkey
  foreign key (etape) references kredi.etapes_dossier(libelle) on update cascade;

-- ---------------------------------------------------------------------
-- 2. Helpers
-- ---------------------------------------------------------------------
-- Ceux qui peuvent passer outre les règles : Admin, ou le système (SQL / service_role / triggers)
create or replace function kredi.contourne_regles()
returns boolean language sql stable security definer set search_path = kredi, public as $$
  select auth.uid() is null
      or coalesce(current_setting('kredi.systeme', true), '') = 'on'
      or kredi.mon_role() = 'Admin'
$$;

create or replace function kredi.statut_ok(s text)
returns boolean language sql immutable as $$ select s in ('Conforme','Non applicable') $$;

-- nombre d'étapes actives Conforme / Non applicable (= « Conformité OK », sur 17)
create or replace function kredi.nb_etapes_ok(p_formulaire uuid)
returns int language sql stable as $$
  select count(*)::int from kredi.validations v join kredi.etapes_validation e on e.num = v.num_etape
  where v.id_formulaire = p_formulaire and e.actif and kredi.statut_ok(v.statut)
$$;

create or replace function kredi.nb_etapes_actives()
returns int language sql stable as $$ select count(*)::int from kredi.etapes_validation where actif $$;

-- état de chaque phase : 'open' | 'done' | 'locked'  (= phaseState() du HTML)
create or replace function kredi.etat_phase(p_formulaire uuid, p_phase smallint)
returns text language sql stable as $$
  with g as (
    select bool_or(num_etape = 4 and statut = 'Conforme') g4,
           bool_or(num_etape = 7 and statut = 'Conforme') g7
    from kredi.validations where id_formulaire = p_formulaire)
  select case p_phase
    when 1 then case when g4 then 'done' else 'open' end
    when 2 then case when not coalesce(g4,false) then 'locked' when g7 then 'done' else 'open' end
    when 3 then case when not coalesce(g7,false) then 'locked' else 'open' end
  end from g
$$;

-- ---------------------------------------------------------------------
-- 3. Formulaire : numéro FC, liens client, création de la fiche de validation
-- ---------------------------------------------------------------------
create or replace function kredi.formulaire_avant_insert()
returns trigger language plpgsql security definer set search_path = kredi, public as $$
declare nc text;
begin
  -- relie le compte épargne / la personne à partir du N° de compte saisi
  if new.id_compte_epargne is null and new.numero_epargne is not null then
    select ce.id_compte_epargne, ce.id_personne into new.id_compte_epargne, new.id_personne
    from public.comptes_epargne ce where upper(ce.no_compte) = upper(trim(new.numero_epargne)) limit 1;
  end if;
  if new.id_personne is null and new.id_compte_epargne is not null then
    select id_personne into new.id_personne from public.comptes_epargne where id_compte_epargne = new.id_compte_epargne;
  end if;
  -- N° dossier : même formule qu'Airtable → FC-<initiale nom><initiale prénom>-00042
  if new.numero_dossier is null then
    nc := trim(coalesce(new.nom,'')) || ' ' || trim(coalesce(new.prenom,''));
    new.numero_dossier := upper('FC-' || left(trim(nc),1) || coalesce(substr(split_part(trim(nc),' ',2),1,1),'') || '-' || lpad(new.numero::text, 5, '0'));
  end if;
  return new;
end $$;
create trigger t_avant_insert before insert on kredi.formulaires for each row execute function kredi.formulaire_avant_insert();

create or replace function kredi.formulaire_apres_insert()
returns trigger language plpgsql security definer set search_path = kredi, public as $$
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
  perform set_config('kredi.systeme','',true);
  return null;
end $$;
create trigger t_apres_insert after insert on kredi.formulaires for each row execute function kredi.formulaire_apres_insert();

-- ---------------------------------------------------------------------
-- 4. Étapes automatiques (1, 7, 15, 17, 18) — recalculées par la base
-- ---------------------------------------------------------------------
create or replace function kredi.recalculer_etapes_auto(p_formulaire uuid)
returns void language plpgsql security definer set search_path = kredi, public as $$
declare
  f  kredi.formulaires;
  rk kredi.risques;
  sc kredi.scorings;
  rc kredi.rapports_cloture;
  renouv boolean;
  s7 text; s15 text; s17 text; s18 text;
begin
  select * into f from kredi.formulaires where id = p_formulaire;
  if not found then return; end if;
  renouv := coalesce(f.type_demande,'') = 'Renouvellement';
  select * into rk from kredi.risques where id_formulaire = p_formulaire;
  select * into sc from kredi.scorings where id_formulaire = p_formulaire;
  select * into rc from kredi.rapports_cloture where id_formulaire = p_formulaire order by numero desc limit 1;

  -- 07 : rapport de risques complet (niveau global + synthèse), seulement si la phase 2 est ouverte
  s7 := case when kredi.etat_phase(p_formulaire, 2::smallint) <> 'locked'
                  and rk.niveau_global is not null and coalesce(trim(rk.synthese),'') <> '' then 'Conforme' else 'À faire' end;
  -- 17 / 18 : rapport de clôture (renouvellement uniquement)
  s17 := case when not renouv then 'Non applicable'
              when rc.verification_am = 'Conforme' then 'Conforme' else 'À faire' end;
  s18 := case when not renouv then 'Non applicable'
              when rc.attestation_remboursement and coalesce(rc.solde_restant,0) = 0 then 'Conforme' else 'À faire' end;

  perform set_config('kredi.systeme','on',true);
  update kredi.validations set statut = s7,  verifie_par = 'Système', date_verification = current_date
   where id_formulaire = p_formulaire and num_etape = 7  and statut is distinct from s7;
  update kredi.validations set statut = s17, verifie_par = 'Système', date_verification = current_date
   where id_formulaire = p_formulaire and num_etape = 17 and statut is distinct from s17;
  update kredi.validations set statut = s18, verifie_par = 'Système', date_verification = current_date
   where id_formulaire = p_formulaire and num_etape = 18 and statut is distinct from s18;
  -- 15 : grille de scoring (phase 3, donc après la porte 07)
  s15 := case when kredi.etat_phase(p_formulaire, 3::smallint) <> 'locked' and sc.id is not null then 'Conforme' else 'À faire' end;
  update kredi.validations set statut = s15, verifie_par = coalesce(sc.evalue_par,'Système'), date_verification = coalesce(sc.date_evaluation,current_date)
   where id_formulaire = p_formulaire and num_etape = 15 and statut is distinct from s15;
  perform set_config('kredi.systeme','',true);
end $$;

create or replace function kredi.trg_recalcul_auto()
returns trigger language plpgsql security definer set search_path = kredi, public as $$
begin
  if pg_trigger_depth() > 3 then return null; end if;
  if tg_op = 'DELETE' then
    if old.id_formulaire is not null then perform kredi.recalculer_etapes_auto(old.id_formulaire); end if;
  else
    if new.id_formulaire is not null then perform kredi.recalculer_etapes_auto(new.id_formulaire); end if;
    if tg_op = 'UPDATE' and old.id_formulaire is distinct from new.id_formulaire and old.id_formulaire is not null then
      perform kredi.recalculer_etapes_auto(old.id_formulaire);
    end if;
  end if;
  return null;
end $$;
create trigger t_auto after insert or update or delete on kredi.scorings         for each row execute function kredi.trg_recalcul_auto();
create trigger t_auto after insert or update or delete on kredi.risques          for each row execute function kredi.trg_recalcul_auto();
create trigger t_auto after insert or update or delete on kredi.rapports_cloture for each row execute function kredi.trg_recalcul_auto();

-- ---------------------------------------------------------------------
-- 5. Fiche de validation : verrouillage des phases + étapes automatiques protégées
-- ---------------------------------------------------------------------
create or replace function kredi.validation_regles()
returns trigger language plpgsql security definer set search_path = kredi, public as $$
declare e kredi.etapes_validation; etat text;
begin
  if kredi.contourne_regles() then return new; end if;
  select * into e from kredi.etapes_validation where num = new.num_etape;
  if tg_op = 'UPDATE' and new.statut is not distinct from old.statut then return new; end if;
  if e.automatique then
    raise exception 'Étape % : statut géré automatiquement par le système', e.libelle using errcode = 'P0001';
  end if;
  if e.phase is not null and new.statut <> 'À faire' then
    etat := kredi.etat_phase(new.id_formulaire, e.phase);
    if etat = 'locked' then
      raise exception '% est verrouillée : la porte de la phase précédente (étape %) doit être Conforme d''abord',
        (select titre from kredi.phases where num = e.phase), lpad((select porte_etape from kredi.phases where num = e.phase - 1)::text,2,'0')
        using errcode = 'P0001';
    end if;
  end if;
  if new.statut <> 'À faire' and new.date_verification is null then new.date_verification := current_date; end if;
  return new;
end $$;
create trigger t_regles before insert or update on kredi.validations for each row execute function kredi.validation_regles();

-- quand la porte 04 ou 07 change, les étapes automatiques des phases suivantes sont recalculées
create or replace function kredi.validation_apres()
returns trigger language plpgsql security definer set search_path = kredi, public as $$
begin
  if pg_trigger_depth() > 3 then return null; end if;
  if new.num_etape in (4,7) and new.statut is distinct from old.statut then
    perform kredi.recalculer_etapes_auto(new.id_formulaire);
  end if;
  return null;
end $$;
create trigger t_apres after update on kredi.validations for each row execute function kredi.validation_apres();

-- ---------------------------------------------------------------------
-- 6. Formulaire : circuit des étapes et décisions (doDecAM / doDecMgr du HTML)
-- ---------------------------------------------------------------------
create or replace function kredi.formulaire_regles()
returns trigger language plpgsql security definer set search_path = kredi, public as $$
declare
  e_old smallint := left(old.etape,1)::smallint;
  e_new smallint := left(new.etape,1)::smallint;
  role  text := kredi.mon_role();
  n_ok  int;
begin
  -- type de demande changé → étapes 17/18 recalculées (après la mise à jour)
  if kredi.contourne_regles() then return new; end if;

  -- 1) transitions d'étape autorisées
  if e_new <> e_old and (e_old, e_new) not in ((1,2),(2,1),(2,3),(3,4),(3,5),(4,3),(4,5)) then
    raise exception 'Passage d''étape interdit : « % » → « % »', old.etape, new.etape using errcode = 'P0001';
  end if;

  -- 2) décision de l'AM
  if new.decision_am is distinct from old.decision_am and new.decision_am is not null then
    if role not in ('Assistant Manager','Manager') then
      raise exception 'Seul un Assistant Manager peut enregistrer la décision AM' using errcode = 'P0001';
    end if;
    if old.etape <> '3 - En analyse (AM)' then
      raise exception 'La décision AM se prend à l''étape « 3 - En analyse (AM) »' using errcode = 'P0001';
    end if;
    if new.decision_am <> 'Validé' and coalesce(trim(new.commentaire_am),'') = '' then
      raise exception 'Le commentaire est obligatoire pour la décision « % »', new.decision_am using errcode = 'P0001';
    end if;
    if new.decision_am = 'Validé' then
      n_ok := kredi.nb_etapes_ok(new.id);
      if n_ok < kredi.nb_etapes_actives() then
        raise exception 'Impossible de valider : fiche de validation %/% — toutes les étapes doivent être Conforme ou Non applicable', n_ok, kredi.nb_etapes_actives() using errcode = 'P0001';
      end if;
      if new.montant_accorde is null then
        raise exception 'Impossible de valider : les conditions du crédit (montant accordé…) ne sont pas saisies' using errcode = 'P0001';
      end if;
      if new.delai_conformite_am is null then
        raise exception 'Indiquez le délai de suivi de conformité (1 à 30 jours ouvrables)' using errcode = 'P0001';
      end if;
    end if;
    if new.decision_am = 'Ajourné' and new.delai_ajournement_am is null then
      raise exception 'Ajournement : indiquez le délai pour lever la cause' using errcode = 'P0001';
    end if;
  end if;
  if e_new = 4 and e_old = 3 and new.decision_am is distinct from 'Validé' then
    raise exception 'Le dossier ne part au Manager qu''après la décision AM « Validé »' using errcode = 'P0001';
  end if;
  if e_new = 5 and e_old = 3 and new.decision_am is distinct from 'Non validé' then
    raise exception 'Depuis l''analyse AM, le dossier ne se clôture que sur « Non validé »' using errcode = 'P0001';
  end if;

  -- 3) décision du Manager
  if new.decision_manager is distinct from old.decision_manager and new.decision_manager is not null then
    if role is distinct from 'Manager' then
      raise exception 'Seul le Manager peut enregistrer la décision finale' using errcode = 'P0001';
    end if;
    if old.etape not in ('4 - En validation (Manager)','5 - Clôturé') then
      raise exception 'La décision du Manager se prend à l''étape « 4 - En validation (Manager) »' using errcode = 'P0001';
    end if;
    if new.commentaire_manager is not distinct from old.commentaire_manager
       or length(coalesce(new.commentaire_manager,'')) - length(coalesce(old.commentaire_manager,'')) < 30 then
      raise exception 'Justificatif obligatoire : expliquez la décision (30 caractères minimum)' using errcode = 'P0001';
    end if;
    if new.decision_manager = 'Retour à l''AM' and (new.delai_retour_manager is null or new.delai_retour_manager < current_date) then
      raise exception 'Retour à l''AM : fixez un délai de réanalyse (pas dans le passé)' using errcode = 'P0001';
    end if;
    if old.decision_manager is null and new.type_demande = 'Renouvellement' and not exists (
         select 1 from kredi.rapports_cloture rc where rc.id_formulaire = new.id and rc.verification_am = 'Conforme') then
      raise exception 'Renouvellement : le rapport de clôture doit être vérifié Conforme par l''AM avant la décision finale' using errcode = 'P0001';
    end if;
  end if;
  if e_new = 5 and e_old = 4 and new.decision_manager not in ('Approuvé','Rejeté') then
    raise exception 'Le dossier se clôture sur la décision du Manager « Approuvé » ou « Rejeté »' using errcode = 'P0001';
  end if;
  if e_new = 3 and e_old = 4 and new.decision_manager is distinct from 'Retour à l''AM' then
    raise exception 'Le retour en analyse se fait par la décision « Retour à l''AM »' using errcode = 'P0001';
  end if;

  return new;
end $$;
create trigger t_regles before update on kredi.formulaires for each row execute function kredi.formulaire_regles();

-- journal + recalcul après mise à jour
create or replace function kredi.formulaire_apres_update()
returns trigger language plpgsql security definer set search_path = kredi, public as $$
begin
  if new.etape is distinct from old.etape then
    insert into kredi.historique_dossier (id_formulaire, champ, ancienne, nouvelle) values (new.id,'etape',old.etape,new.etape);
  end if;
  if new.decision_am is distinct from old.decision_am then
    insert into kredi.historique_dossier (id_formulaire, champ, ancienne, nouvelle) values (new.id,'decision_am',old.decision_am,new.decision_am);
  end if;
  if new.decision_manager is distinct from old.decision_manager then
    insert into kredi.historique_dossier (id_formulaire, champ, ancienne, nouvelle) values (new.id,'decision_manager',old.decision_manager,new.decision_manager);
  end if;
  if new.finance_etape is distinct from old.finance_etape then
    insert into kredi.historique_dossier (id_formulaire, champ, ancienne, nouvelle) values (new.id,'finance_etape',old.finance_etape,new.finance_etape);
  end if;
  if new.type_demande is distinct from old.type_demande and pg_trigger_depth() <= 3 then
    perform kredi.recalculer_etapes_auto(new.id);
  end if;
  return null;
end $$;
create trigger t_apres_update after update on kredi.formulaires for each row execute function kredi.formulaire_apres_update();
