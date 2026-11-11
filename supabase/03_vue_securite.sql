-- =====================================================================
--  SCHEMA « kredi » — 3/3 : vue de suivi (champs calculés) + sécurité
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Vue de suivi : reprend les formules Airtable (délais, statuts, conformité, score)
-- ---------------------------------------------------------------------
create or replace view kredi.v_formulaires with (security_invoker = true) as
with b as (
  select f.*,
    trim(coalesce(f.nom,'')) || ' ' || trim(coalesce(f.prenom,''))                  as nom_complet,
    'FC-' || right(coalesce(f.numero_epargne,''), 6)                                  as id_formulaire,
    kredi.ajout_jours_ouvrables(f.date_remise,   case when f.type_demande = 'Renouvellement' then 1 else 2 end) as date_retour_attendue,
    kredi.ajout_jours_ouvrables(f.date_debut_am, case when f.type_demande = 'Renouvellement' then 2 else 3 end) as deadline_am,
    kredi.ajout_jours_ouvrables(f.date_envoi_manager, 2)                              as deadline_manager
  from kredi.formulaires f
)
select b.*,
  -- Statut Délai
  case b.etape
    when '1 - Formulaire remis à l''agent' then case when b.date_retour_attendue < current_date then 'Retard agent' else 'Attente agent' end
    when '2 - Retourné au secrétariat'     then 'A prendre par AM'
    when '3 - En analyse (AM)'             then case when b.deadline_am < current_date then 'Retard AM' else 'Analyse AM' end
    when '4 - En validation (Manager)'     then case when b.deadline_manager < current_date then 'Retard Manager' else 'Validation Manager' end
    when '5 - Clôturé'                     then 'Clôturé'
  end as statut_delai,
  -- Statut Suivi (secrétariat)
  case
    when b.etape = '5 - Clôturé' then 'Clôturé'
    when coalesce(b.motif_blocage,'') <> '' then 'Bloqué'
    when b.etape = '1 - Formulaire remis à l''agent' then
      case when b.date_retour_attendue is null then 'En cours'
           when b.date_retour_attendue = current_date then 'À remettre aujourd''hui'
           when b.date_retour_attendue < current_date then 'En retard' else 'En cours' end
    when coalesce(b.nom,'') = '' or coalesce(b.prenom,'') = '' or coalesce(b.numero_epargne,'') = '' or cardinality(b.documents_recus) = 0 then 'À compléter'
    when b.date_retour > b.date_retour_attendue then 'Remis en retard'
    else 'Remis à temps'
  end as statut_suivi,
  -- Statut AM
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
  -- Respect des délais
  nullif(concat_ws(' | ',
    case when b.date_retour is not null then 'Agent:' || case when b.date_retour > b.date_retour_attendue then 'KO' else 'OK' end end,
    case when b.date_decision_am is not null then 'AM:' || case when b.date_decision_am > b.deadline_am then 'KO' else 'OK' end end,
    case when b.date_decision_manager is not null then 'Mgr:' || case when b.date_decision_manager > b.deadline_manager then 'KO' else 'OK' end end), '') as respect_delais,
  kredi.jours_ouvrables_entre(b.date_remise, coalesce(b.date_retour, current_date))           as jours_utilises,
  greatest(0, coalesce(kredi.jours_ouvrables_entre(b.date_retour_attendue, coalesce(b.date_retour, current_date)),0)) as retard_jours,
  kredi.jours_ouvrables_entre(b.date_debut_am, coalesce(b.date_decision_am, current_date))    as jours_am_utilises,
  case when b.deadline_am < coalesce(b.date_decision_am, current_date) then coalesce(b.date_decision_am, current_date) - b.deadline_am else 0 end as retard_am_jours,
  -- Conformité, score, montants
  kredi.nb_etapes_ok(b.id)                                                     as conformite_ok,
  round(kredi.nb_etapes_ok(b.id) * 100.0 / kredi.nb_etapes_actives())          as conformite_pct,
  (select s.score_total from kredi.scorings s where s.id_formulaire = b.id)    as score_credit,
  case when coalesce(b.montant_accorde, b.montant_demande) is not null and b.taux_fonds_garantie is not null
       then round(coalesce(b.montant_accorde, b.montant_demande) * b.taux_fonds_garantie / 100) end as montant_fdg_requis,
  case when b.montant_accorde is not null
       then round(b.montant_accorde * (1 + coalesce(b.taux_interet,0) / 100 * coalesce(nullif(b.duree_mois,0),1))) end as montant_total_am,
  (select d.num_ds from kredi.dossiers_clients d where d.id = b.id_dossier_client) as num_ds
from b;

-- Fiche de validation lisible (étape, phase, ordre 1.1 / 2.3 …)
create or replace view kredi.v_fiche_validation with (security_invoker = true) as
select v.*, e.libelle as etape, e.phase, e.phase || '.' || e.ordre as numero_affiche,
       e.est_porte, e.automatique, e.renouvellement_seulement,
       kredi.etat_phase(v.id_formulaire, e.phase) as etat_phase
from kredi.validations v join kredi.etapes_validation e on e.num = v.num_etape
where e.actif;

create or replace view kredi.v_scorings with (security_invoker = true) as
select s.*,
  case when s.score_total >= 80 then 'Activité stable — Crédit recommandé'
       when s.score_total >= 65 then 'Moyennement stable — Crédit avec conditions'
       when s.score_total >= 50 then 'Risqué — Prudence'
       else 'Très risqué — Refus' end as decision_selon_score
from kredi.scorings s;

-- ---------------------------------------------------------------------
-- 2. Droits & RLS : seuls les utilisateurs actifs de kredi.utilisateurs accèdent aux données
-- ---------------------------------------------------------------------
grant usage on schema kredi to authenticated, service_role;
grant select, insert, update on all tables in schema kredi to authenticated;
grant delete on kredi.validations, kredi.scorings, kredi.risques, kredi.rapports_cloture, kredi.frais_dossier, kredi.contrats, kredi.formulaires, kredi.parametres, kredi.dossiers_clients, kredi.utilisateurs to authenticated;
grant all on all tables in schema kredi to service_role;
grant usage, select on all sequences in schema kredi to authenticated, service_role;
grant execute on all functions in schema kredi to authenticated, service_role;
revoke insert, update, delete on kredi.phases, kredi.etapes_validation, kredi.etapes_dossier, kredi.historique_dossier from authenticated;

do $$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'kredi' loop
    execute format('alter table kredi.%I enable row level security', t);
  end loop;
  -- tables de données : lecture / écriture pour les utilisateurs actifs, suppression Admin
  for t in select unnest(array['formulaires','validations','scorings','risques','rapports_cloture','contrats','frais_dossier','dossiers_clients','parametres']) loop
    execute format('create policy lecture on kredi.%I for select to authenticated using (kredi.est_utilisateur_actif())', t);
    execute format('create policy ajout on kredi.%I for insert to authenticated with check (kredi.est_utilisateur_actif())', t);
    execute format('create policy modif on kredi.%I for update to authenticated using (kredi.est_utilisateur_actif()) with check (kredi.est_utilisateur_actif())', t);
    execute format('create policy suppression on kredi.%I for delete to authenticated using (kredi.mon_role() = ''Admin'')', t);
  end loop;
end $$;

-- référentiel : lecture pour tout utilisateur connecté
create policy lecture on kredi.phases            for select to authenticated using (true);
create policy lecture on kredi.etapes_validation for select to authenticated using (true);
create policy lecture on kredi.etapes_dossier    for select to authenticated using (true);
create policy lecture on kredi.historique_dossier for select to authenticated using (kredi.est_utilisateur_actif());

-- utilisateurs : chacun voit sa fiche ; Admin gère tout le monde
create policy moi        on kredi.utilisateurs for select to authenticated using (user_id = auth.uid() or kredi.est_utilisateur_actif());
create policy admin_ajout on kredi.utilisateurs for insert to authenticated with check (kredi.mon_role() = 'Admin');
create policy admin_modif on kredi.utilisateurs for update to authenticated using (kredi.mon_role() = 'Admin' or user_id = auth.uid()) with check (kredi.mon_role() = 'Admin' or user_id = auth.uid());
create policy admin_supp  on kredi.utilisateurs for delete to authenticated using (kredi.mon_role() = 'Admin');

-- un utilisateur non-Admin ne peut pas changer son propre rôle / statut
create or replace function kredi.utilisateur_protege()
returns trigger language plpgsql security definer set search_path = kredi, public as $$
begin
  if kredi.contourne_regles() then return new; end if;
  if new.role is distinct from old.role or new.actif is distinct from old.actif or new.equipe_am is distinct from old.equipe_am or new.identifiant is distinct from old.identifiant then
    raise exception 'Seul un Admin peut modifier le rôle, l''équipe ou le statut d''un utilisateur' using errcode = 'P0001';
  end if;
  return new;
end $$;
create trigger t_protege before update on kredi.utilisateurs for each row execute function kredi.utilisateur_protege();

-- ---------------------------------------------------------------------
-- 3. Stockage privé des documents scannés (remplace les pièces jointes Airtable)
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public) values ('kredi-documents','kredi-documents', false)
on conflict (id) do nothing;

create policy kredi_docs_lecture on storage.objects for select to authenticated
  using (bucket_id = 'kredi-documents' and kredi.est_utilisateur_actif());
create policy kredi_docs_ajout on storage.objects for insert to authenticated
  with check (bucket_id = 'kredi-documents' and kredi.est_utilisateur_actif());
create policy kredi_docs_supp on storage.objects for delete to authenticated
  using (bucket_id = 'kredi-documents' and kredi.mon_role() = 'Admin');
