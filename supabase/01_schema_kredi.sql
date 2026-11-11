-- =====================================================================
--  SCHEMA « kredi » — Suivi Analyse Crédit (port de l'app HTML v1.52.1)
--  Projet Supabase : Debloke Test
--  Source : base Airtable « Credit » (appU8un1ZZoWZT35n) + logique du HTML
-- =====================================================================
create schema if not exists kredi;
comment on schema kredi is 'Suivi analyse crédit : formulaires, fiche de validation (3 phases), scoring, risques, rapports de clôture, contrats, finance.';

-- ---------------------------------------------------------------------
-- 0. Fonctions utilitaires (mêmes calculs que les formules Airtable)
-- ---------------------------------------------------------------------
-- DATEADD(d, n + IF(WEEKDAY(d)+n >= 7, 1, 0)) : saute le dimanche
create or replace function kredi.ajout_jours_ouvrables(d date, n int)
returns date language sql immutable as $$
  select case when d is null then null
              else d + n + case when extract(dow from d)::int + n >= 7 then 1 else 0 end end
$$;

-- jours écoulés sans les dimanches : diff - FLOOR((diff + WEEKDAY(debut)) / 7)
create or replace function kredi.jours_ouvrables_entre(debut date, fin date)
returns int language sql immutable as $$
  select case when debut is null or fin is null then null
              else (fin - debut) - floor(((fin - debut) + extract(dow from debut)::int) / 7.0)::int end
$$;

-- reproduction de la formule Airtable « Clé Client » (anti-doublon DS)
create or replace function kredi.cle_client(t text)
returns text language plpgsql immutable as $$
declare x text := lower(trim(coalesce(t,'')));
begin
  x := translate(x, 'éèêëàâäîïôöùûüç-.''', 'eeeeaaaiioouuuc   ');
  x := regexp_replace(x, '[^a-z ]', '', 'g');
  x := regexp_replace(x, ' +', ' ', 'g');
  x := regexp_replace(x, '\mst\M', 'saint', 'g');
  x := replace(x,'ph','f'); x := replace(x,'qu','k'); x := replace(x,'ck','k');
  x := replace(x,'y','i');  x := replace(x,'w','v');  x := replace(x,'z','s'); x := replace(x,'h','');
  x := regexp_replace(x, 'c([eiy])', 's\1', 'g');
  x := replace(x,'c','k'); x := replace(x,'ou','u'); x := replace(x,'eau','o'); x := replace(x,'au','o');
  x := replace(x,'ai','e'); x := replace(x,'ei','e');
  x := regexp_replace(x, '([bdfgklmnprst])\1', '\1', 'g');
  x := regexp_replace(x, 'e\M', '', 'g');
  x := regexp_replace(x, '[dts]\M', '', 'g');
  return trim(x);
end $$;

create or replace function kredi.touch_updated_at()
returns trigger language plpgsql as $$ begin new.updated_at := now(); return new; end $$;

-- ---------------------------------------------------------------------
-- 1. Référentiel de la démarche (phases / étapes) — reflète PHASES et ETAPES_V du HTML
-- ---------------------------------------------------------------------
create table kredi.phases (
  num          smallint primary key,
  titre        text not null,
  description  text,
  porte_etape  smallint            -- étape « porte » qui ouvre la phase suivante (null = dernière phase)
);

create table kredi.etapes_validation (
  num          smallint primary key check (num between 1 and 20),
  libelle      text not null unique,          -- ex. « 04 - Validation du suivi du formulaire »
  description  text,
  phase        smallint references kredi.phases(num),
  ordre        smallint,                      -- position dans la phase (1.1, 1.2 …)
  est_porte    boolean not null default false,
  automatique  boolean not null default false, -- statut géré par le système (1, 7, 15, 17, 18)
  renouvellement_seulement boolean not null default false,
  actif        boolean not null default true  -- 10, 11, 14 retirées (gérées par Finance / Secrétariat)
);

-- Étapes du dossier (champ « Étape Analyse »)
create table kredi.etapes_dossier (
  num      smallint primary key,
  libelle  text not null unique
);

-- ---------------------------------------------------------------------
-- 2. Utilisateurs de l'application (liés à Supabase Auth)
-- ---------------------------------------------------------------------
create table kredi.utilisateurs (
  user_id            uuid primary key references auth.users(id) on delete cascade,
  identifiant        text not null unique,
  nom_complet        text not null,
  role               text not null check (role in ('Secrétaire','Assistant Manager','Manager','Admin','Agent de recouvrement','Responsable Finance')),
  equipe_am          text,                              -- Emmanuel / Louvenso / Administration …
  actif              boolean not null default true,
  doit_changer_mdp   boolean not null default false,
  derniere_connexion timestamptz,
  created_at         timestamptz not null default now(),
  airtable_id        text unique
);

create or replace function kredi.mon_role()
returns text language sql stable security definer set search_path = kredi, public as $$
  select role from kredi.utilisateurs where user_id = auth.uid() and actif
$$;

create or replace function kredi.est_utilisateur_actif()
returns boolean language sql stable security definer set search_path = kredi, public as $$
  select exists(select 1 from kredi.utilisateurs where user_id = auth.uid() and actif)
$$;

-- ---------------------------------------------------------------------
-- 3. Paramètres (table « Paramètres Suivi » : clé / valeur JSON)
-- ---------------------------------------------------------------------
create table kredi.parametres (
  cle          text primary key,
  valeur       text,
  modifie_par  text,
  modifie_le   timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 4. Dossier client (DS-xxxxx) — un client, plusieurs formulaires / crédits
-- ---------------------------------------------------------------------
create table kredi.dossiers_clients (
  id            uuid primary key default gen_random_uuid(),
  numero        int generated always as identity unique,
  num_ds        text generated always as ('DS-' || lpad(numero::text, 5, '0')) stored,
  id_personne   uuid references public.personnes(id_personne),
  nom           text not null,
  zone          text,
  lieu_travail  text,
  cle_client    text generated always as (kredi.cle_client(nom)) stored,
  statut        text,
  created_at    timestamptz not null default now(),
  airtable_id   text unique
);
create index on kredi.dossiers_clients (cle_client);
create index on kredi.dossiers_clients (id_personne);

-- ---------------------------------------------------------------------
-- 5. FORMULAIRE DE CRÉDIT (FC-xx-xxxxx) — le dossier d'analyse
-- ---------------------------------------------------------------------
create table kredi.formulaires (
  id                    uuid primary key default gen_random_uuid(),
  numero                int generated always as identity unique,      -- « ID » autonumber
  numero_dossier        text unique,                                  -- FC-<initiales>-00042 (trigger)

  -- Client & demande
  id_personne           uuid references public.personnes(id_personne),
  id_compte_epargne     uuid references public.comptes_epargne(id_compte_epargne),
  id_dossier_client     uuid references kredi.dossiers_clients(id),
  numero_epargne        text,                    -- A-BSI… / A-BSG… (Grandon)
  nom                   text,
  prenom                text,
  zone                  text,
  lieu_travail          text,
  type_demande          text check (type_demande in ('Nouveau','Renouvellement')),
  type_credit           text,
  mention_credit        text check (mention_credit in ('Renouvellement','Premier Crédit','Blacklist')),
  montant_demande       numeric(14,2),
  date_demande          date,
  agent_credit          text,
  agent_epargne         text,
  liste_documents       text[],
  document_domicile     text,
  controle_ds           text,

  -- Secrétariat : remise / retour du formulaire
  etape                 text not null default '1 - Formulaire remis à l''agent',   -- FK vers etapes_dossier ajoutée en 02
  date_remise           date,
  remis_par             text,
  date_retour           date,
  retour_par            text,
  documents_recus       text[] not null default '{}',
  documents_detail      jsonb,
  documents_scannes     jsonb not null default '[]',   -- [{path, nom, type, ajoute_le}] → Supabase Storage
  raison_retard         text,
  motif_blocage         text,
  observation_blocage   text,
  date_blocage          date,
  date_levee_blocage    date,

  -- Assistant Manager (AM)
  am_assigne            text,
  date_debut_am         date,
  decision_am           text check (decision_am in ('Validé','Non validé','Ajourné')),
  date_decision_am      date,
  commentaire_am        text,
  delai_ajournement_am  date,
  delai_conformite_am   smallint check (delai_conformite_am between 1 and 30),
  date_limite_conformite date,
  -- conditions du crédit proposées par l'AM (étape 13)
  montant_accorde       numeric(14,2),
  duree_mois            numeric(6,2),
  taux_interet          numeric(6,3),
  paiement_jour         numeric(14,2),
  nombre_versements     int,
  dernier_versement     numeric(14,2),
  taux_fonds_garantie   numeric(6,3),
  source_fonds_garantie text check (source_fonds_garantie in ('Compte épargne','Compte fonds de garantie','Insuffisant','Compte fonds de garantie + Compte épargne')),
  compte_fdg_correction text,

  -- Manager
  date_envoi_manager    date,
  decision_manager      text check (decision_manager in ('Approuvé','Rejeté','Retour à l''AM')),
  date_decision_manager date,
  commentaire_manager   text,
  delai_retour_manager  date,

  -- Correspondance (secrétariat) : lettres AR / LV / RD / LC / PM, RDV de décaissement
  ref_lettre_ar         text,
  lettre_ar_le          date,
  ref_lettre_lv         text,
  ref_lettre_rd         text,
  ref_lettre_lc         text,
  ref_lettre_pm         text,
  lettre_generee_le     date,
  lettre_generee_par    text,
  lettre_statut         text check (lettre_statut in ('Générée','Remise à l''agent','Retournée signée','Retournée non signée','RDV décaissement envoyé')),
  lettre_remise_le      date,
  lettre_retournee_le   date,
  lettre_motif_non_signature text,
  rdv_decaissement      timestamptz,
  lettre_rdv_le         date,
  autorisation_admin_rdv text,
  statut_rdv            text check (statut_rdv in ('Planifié','Lettre envoyée','Honoré — décaissé','Manqué','Reporté','Annulé')),
  note_rdv              text,
  donnees_lettres       jsonb,

  -- Finance
  finance_etape         text check (finance_etape in ('1 - Vérification frais & FDG','1b - En attente de régularisation','2 - Contrôle de conformité','2b - Correction demandée','3 - Ordre de décaissement à émettre','4 - Ordre transmis au Responsable Finance','5 - Décaissement autorisé','5x - Décaissement refusé')),
  ref_ordre_od          text,
  decision_finance      text check (decision_finance in ('Autorisé','Refusé')),
  date_decaissement     date,
  donnees_finance       jsonb,

  -- Contrat
  ref_contrat_ct        text,
  statut_contrat        text check (statut_contrat in ('Généré','Signé','Annulé')),
  donnees_contrat       jsonb,
  id_compte_credit      uuid references public.comptes_credit(id_compte_credit),   -- crédit créé après décaissement

  created_at            timestamptz not null default now(),   -- « Date Soumission »
  updated_at            timestamptz not null default now(),
  airtable_id           text unique
);
create index on kredi.formulaires (etape);
create index on kredi.formulaires (am_assigne);
create index on kredi.formulaires (upper(numero_epargne));
create index on kredi.formulaires (id_dossier_client);
create index on kredi.formulaires (created_at);

-- Historique des changements d'étape / décisions (traçabilité de la démarche)
create table kredi.historique_dossier (
  id            bigint generated always as identity primary key,
  id_formulaire uuid not null references kredi.formulaires(id) on delete cascade,
  champ         text not null,
  ancienne      text,
  nouvelle      text,
  par           uuid default auth.uid(),
  le            timestamptz not null default now()
);
create index on kredi.historique_dossier (id_formulaire, le);

-- ---------------------------------------------------------------------
-- 6. FICHE DE VALIDATION — une ligne par étape (table « Validation Conformité »)
-- ---------------------------------------------------------------------
create table kredi.validations (
  id                 uuid primary key default gen_random_uuid(),
  id_formulaire      uuid not null references kredi.formulaires(id) on delete cascade,
  num_etape          smallint not null references kredi.etapes_validation(num),
  statut             text not null default 'À faire' check (statut in ('À faire','Conforme','Non conforme','Non applicable')),
  criteres_verifies  text[],             -- étape 02 : Clientèle, Réputation…
  date_verification  date,
  verifie_par        text,
  commentaire        text,
  montant            numeric(14,2),
  telephone_confirme text,               -- étapes 19 / 20
  updated_at         timestamptz not null default now(),
  airtable_id        text unique,
  unique (id_formulaire, num_etape)
);

-- ---------------------------------------------------------------------
-- 7. GRILLE DE SCORING /100 (table « Scoring Crédit ») — étape 15
-- ---------------------------------------------------------------------
create table kredi.scorings (
  id              uuid primary key default gen_random_uuid(),
  id_formulaire   uuid not null unique references kredi.formulaires(id) on delete cascade,
  personne_reference text,
  -- A. Description de l'activité (20)
  a1 text, a1_pts numeric(4,1), a1_justif text,
  a2 text, a2_pts numeric(4,1), a2_justif text,
  a3 text, a3_pts numeric(4,1), a3_justif text,
  a4 text, a4_pts numeric(4,1), a4_justif text,
  -- S. Stabilité (20)
  s1 text, s1_pts numeric(4,1), s1_justif text,
  s2 text, s2_pts numeric(4,1), s2_justif text,
  s3 text, s3_pts numeric(4,1), s3_justif text,
  s4 text, s4_pts numeric(4,1), s4_justif text,
  -- Stock
  stock_type text, stock_valeur numeric(14,2), stock_rotation text, stock_perissabilite text,
  stock_adapte text, stock_appreciation text, stock_justif text,
  -- Chiffres du commerce
  ventes_jour numeric(14,2), depenses_jour numeric(14,2), benefice_jour numeric(14,2),
  revenu_mensuel numeric(14,2), depenses_menage numeric(14,2), base_analyse numeric(14,2),
  taux_capacite numeric(5,2),
  -- F. Analyse financière (25)
  f1_pts numeric(4,1), f1_justif text,
  f2_pts numeric(4,1), f2_justif text,
  f3_pts numeric(4,1), f3_justif text,
  f4_pts numeric(4,1), f4_justif text,
  -- M. Comportement & moralité (20)
  m1 text, m1_pts numeric(4,1), m1_justif text,
  m2 text, m2_pts numeric(4,1), m2_justif text,
  m3 text, m3_pts numeric(4,1), m3_justif text,
  -- Garantie (15)
  garantie_type text check (garantie_type in ('Garantie matérielle','Garantie solidaire','Garantie sociale','Aucune')),
  garantie_pts numeric(4,1), garantie_justif text,
  risques_identifies text[], risques_justif text,
  -- Recommandation AM
  montant_recommande numeric(14,2), duree_recommandee numeric(6,2),
  modalite text, modalite_precision text,
  avis_am text, avis_am_justif text,
  decision_am_grille text check (decision_am_grille in ('Accord','Accord sous condition','Refus')),
  decision_am_justif text,
  commentaire text, evalue_par text, date_evaluation date,
  -- Totaux (formules Airtable)
  total_activite  numeric generated always as (coalesce(a1_pts,0)+coalesce(a2_pts,0)+coalesce(a3_pts,0)+coalesce(a4_pts,0)) stored,
  total_stabilite numeric generated always as (coalesce(s1_pts,0)+coalesce(s2_pts,0)+coalesce(s3_pts,0)+coalesce(s4_pts,0)) stored,
  total_financier numeric generated always as (coalesce(f1_pts,0)+coalesce(f2_pts,0)+coalesce(f3_pts,0)+coalesce(f4_pts,0)) stored,
  total_moralite  numeric generated always as (coalesce(m1_pts,0)+coalesce(m2_pts,0)+coalesce(m3_pts,0)) stored,
  score_total     numeric generated always as (
      coalesce(a1_pts,0)+coalesce(a2_pts,0)+coalesce(a3_pts,0)+coalesce(a4_pts,0)
    + coalesce(s1_pts,0)+coalesce(s2_pts,0)+coalesce(s3_pts,0)+coalesce(s4_pts,0)
    + coalesce(f1_pts,0)+coalesce(f2_pts,0)+coalesce(f3_pts,0)+coalesce(f4_pts,0)
    + coalesce(m1_pts,0)+coalesce(m2_pts,0)+coalesce(m3_pts,0)+coalesce(garantie_pts,0)) stored,
  capacite_mensuelle numeric generated always as (case when base_analyse is not null then round(base_analyse * coalesce(taux_capacite,15) / 100) end) stored,
  capacite_jour      numeric generated always as (case when base_analyse is not null then round(round(base_analyse * coalesce(taux_capacite,15) / 100) / 26, 2) end) stored,
  updated_at      timestamptz not null default now(),
  airtable_id     text unique
);

-- ---------------------------------------------------------------------
-- 8. DÉTECTION ET GESTION DES RISQUES (table « Risques Crédit ») — porte de la phase 2 (étape 7)
-- ---------------------------------------------------------------------
create table kredi.risques (
  id               uuid primary key default gen_random_uuid(),
  id_formulaire    uuid not null unique references kredi.formulaires(id) on delete cascade,
  risques_identifies text[],
  r1_explication text, r1_plan text,   -- Incapacité de remboursement réel
  r2_explication text, r2_plan text,   -- Positionnement géographique
  r3_explication text, r3_plan text,   -- Saisonnalité
  r4_explication text, r4_plan text,   -- Surendettement
  r5_explication text, r5_plan text,   -- Utilisation du crédit
  r6_explication text, r6_plan text,   -- Incohérence des transactions
  r7_precision text, r7_explication text, r7_plan text,  -- Autres
  r8_concerne text[], r8_explication text, r8_plan text, -- Moyens de contact
  niveau_global    text check (niveau_global in ('Faible','Modéré','Élevé','Critique')),
  synthese         text,
  evalue_par       text,
  date_evaluation  date,
  updated_at       timestamptz not null default now(),
  airtable_id      text unique
);

-- ---------------------------------------------------------------------
-- 9. RAPPORT DE CLÔTURE du crédit précédent (RC-xxxxx) — renouvellement, étapes 17 / 18
-- ---------------------------------------------------------------------
create table kredi.rapports_cloture (
  id                 uuid primary key default gen_random_uuid(),
  numero             int generated always as identity unique,
  id_rapport         text generated always as ('RC-' || lpad(numero::text, 5, '0')) stored,
  id_formulaire      uuid references kredi.formulaires(id) on delete set null,
  numero_dossier     text,
  client             text,
  numero_epargne     text,
  id_compte_credit   uuid references public.comptes_credit(id_compte_credit),
  id_credit_precedent text,
  agent_recouvrement text,
  statut             text not null default 'À remplir' check (statut in ('À remplir','Rempli','Retourné à l''agent','Vérifié AM')),
  date_creation      date default current_date,
  cree_par           text,
  date_limite        date,
  montant_pret       numeric(14,2),
  montant_total      numeric(14,2),
  montant_rembourse  numeric(14,2),
  solde_restant      numeric(14,2),
  date_debut_credit  date,
  date_fin_credit    date,
  date_dernier_versement date,
  statut_creances    text,
  nombre_retards     int,
  comportement_paiement text,
  observations_agent text,
  recommandation_agent text check (recommandation_agent in ('Favorable au renouvellement','Favorable sous réserve','Défavorable')),
  attestation_remboursement boolean not null default false,
  date_attestation   date,
  atteste_par        text,
  rempli_le          date,
  verification_am    text check (verification_am in ('Conforme','Non conforme')),
  observation_am     text,
  verifie_par        text,
  date_verification  date,
  verifie_par_am     text,
  date_verification_am date,
  observation_manager text,
  donnees_rapport    jsonb,
  score_historique   numeric,
  mode_cloture       text,
  recommandation_renouvellement text,
  modele_rapport     text,
  updated_at         timestamptz not null default now(),
  airtable_id        text unique
);
create index on kredi.rapports_cloture (id_formulaire);
create index on kredi.rapports_cloture (upper(numero_epargne));

-- ---------------------------------------------------------------------
-- 10. CONTRAT DE CRÉDIT (CT-…)
-- ---------------------------------------------------------------------
create table kredi.contrats (
  id                  uuid primary key default gen_random_uuid(),
  numero_credit       text unique,
  id_formulaire       uuid references kredi.formulaires(id) on delete set null,
  id_dossier_client   uuid references kredi.dossiers_clients(id),
  id_compte_epargne   uuid references public.comptes_epargne(id_compte_epargne),
  id_compte_credit    uuid references public.comptes_credit(id_compte_credit),
  numero_formulaire   text,
  nom_client          text,
  prenom_client       text,
  piece_identification text,
  numero_identification text,
  date_naissance      date,
  sexe                text,
  adresse             text,
  telephone           text,
  numero_epargne      text,
  type_credit         text,
  montant             numeric(14,2),
  montant_lettres     text,
  taux_interet        numeric(6,3),
  duree_mois          numeric(6,2),
  paiement_jour       numeric(14,2),
  montant_final       numeric(14,2),
  date_debut          date,
  date_echeance       date,
  modalites           text,
  objet               text,
  fonds_garantie      numeric(14,2),
  penalites           numeric(14,2),
  frais_dossier       numeric(14,2),
  jours_conge         text,
  temoin_nom          text,
  temoin_piece        text,
  temoin_numero       text,
  temoin_adresse      text,
  agent_credit        text,
  agent_epargne       text,
  suivi_remboursement text,
  created_at          timestamptz not null default now(),
  airtable_id         text unique
);

-- ---------------------------------------------------------------------
-- 11. FRAIS DE DOSSIER (ancienne base « Gestion Frais Dossier »)
--     Le fonds de garantie se lit dans public.comptes_epargne.fonds_garantie
-- ---------------------------------------------------------------------
create table kredi.frais_dossier (
  id                uuid primary key default gen_random_uuid(),
  id_formulaire     uuid references kredi.formulaires(id) on delete set null,
  numero_dossier    text,
  numero_epargne    text,
  montant           numeric(14,2),
  date_paiement     date,
  statut            text,
  paye              boolean not null default false,
  collecteur        text,
  created_at        timestamptz not null default now(),
  airtable_id       text unique
);
create index on kredi.frais_dossier (numero_dossier);

-- updated_at
create trigger t_upd before update on kredi.formulaires      for each row execute function kredi.touch_updated_at();
create trigger t_upd before update on kredi.validations      for each row execute function kredi.touch_updated_at();
create trigger t_upd before update on kredi.scorings         for each row execute function kredi.touch_updated_at();
create trigger t_upd before update on kredi.risques          for each row execute function kredi.touch_updated_at();
create trigger t_upd before update on kredi.rapports_cloture for each row execute function kredi.touch_updated_at();
