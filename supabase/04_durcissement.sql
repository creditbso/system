-- =====================================================================
--  SCHEMA « kredi » — 4 : durcissement (recommandations du Security Advisor)
-- =====================================================================
alter function kredi.ajout_jours_ouvrables(date,int) set search_path = '';
alter function kredi.jours_ouvrables_entre(date,date) set search_path = '';
alter function kredi.cle_client(text) set search_path = '';
alter function kredi.touch_updated_at() set search_path = '';
alter function kredi.statut_ok(text) set search_path = '';
alter function kredi.nb_etapes_ok(uuid) set search_path = kredi;
alter function kredi.nb_etapes_actives() set search_path = kredi;
alter function kredi.etat_phase(uuid,smallint) set search_path = kredi;
revoke execute on all functions in schema kredi from public, anon;
revoke execute on function kredi.recalculer_etapes_auto(uuid) from authenticated;
