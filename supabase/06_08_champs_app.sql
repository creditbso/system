-- =====================================================================
--  SCHEMA « kredi » — 6 à 8 : champs attendus par l'application HTML
-- =====================================================================
-- 06
alter table kredi.scorings add column if not exists numero_dossier text;
alter table kredi.risques  add column if not exists numero_dossier text;
alter table kredi.contrats add column if not exists numero int generated always as identity,
                           add column if not exists numero_dossier_client text;
create or replace function kredi.contrat_avant_insert()
returns trigger language plpgsql set search_path = kredi, public as $$
begin
  if new.numero_credit is null then
    new.numero_credit := 'A-SC-' || upper(left(trim(coalesce(new.nom_client,'')),1)) || upper(left(trim(coalesce(new.prenom_client,'')),1))
                         || lpad((345 + new.numero)::text, 5, '0');
  end if;
  return new;
end $$;
create trigger t_avant_insert before insert on kredi.contrats for each row execute function kredi.contrat_avant_insert();
alter table kredi.rapports_cloture drop column id_rapport;
alter table kredi.rapports_cloture add column id_rapport text unique;
create or replace function kredi.rc_avant_insert()
returns trigger language plpgsql set search_path = kredi, public as $$
begin
  if new.id_rapport is null then new.id_rapport := 'RC-' || lpad(new.numero::text, 5, '0'); end if;
  return new;
end $$;
create trigger t_avant_insert before insert on kredi.rapports_cloture for each row execute function kredi.rc_avant_insert();
grant select on kredi.v_scorings, kredi.v_fiche_validation to authenticated;

-- 07 : fonds de garantie (porté par le compte épargne dans Supabase)
create or replace view kredi.ext_fonds_garantie as
select ce.id_compte_epargne as id, ce.created_at, 'FG-' || upper(ce.no_compte) as id_compte,
  coalesce(ce.fonds_garantie,0) as solde, array[upper(ce.no_compte)] as comptes_epargne, p.nom, p.prenom
from public.comptes_epargne ce left join public.personnes p on p.id_personne = ce.id_personne
where kredi.est_utilisateur_actif();
grant select on kredi.ext_fonds_garantie to authenticated;

-- 08
alter table kredi.frais_dossier add column if not exists montant_paye numeric(14,2);

-- Exposition du schéma à l'API (équivaut à Settings → API → Exposed schemas)
alter role authenticator set pgrst.db_schemas = 'public, graphql_public, kredi';
notify pgrst, 'reload config';
