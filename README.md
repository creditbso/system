# Suivi Analyse Crédit — Bwat Sekrèm

Application de suivi des demandes de crédit (secrétariat, Assistant Manager, Manager, Finance, recouvrement).
Données : Supabase, projet **Debloke Test**, schéma `kredi`.

## En ligne
Publiée par GitHub Pages depuis `index.html` (branche `main`, dossier racine).

## Connexion
Chaque utilisateur se connecte avec son identifiant et son mot de passe (Supabase Auth).
Les comptes sont créés par l'Admin dans l'application. Sans compte actif dans `kredi.utilisateurs`, aucune donnée n'est visible (RLS).

## Contenu
- `index.html` — l'application (bibliothèque Supabase incluse, aucun serveur nécessaire)
- `supabase/` — migrations SQL du schéma `kredi` (01 → 08), dans l'ordre
- `build/` — script qui produit `index.html` à partir du HTML Airtable v1.52.1 :
  `python3 build/build.py <html_airtable> index.html`
