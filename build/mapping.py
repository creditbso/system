# Génère sb_mapping.js : correspondance champ Airtable (id + nom) -> colonne Supabase
import json, re, sys

AT = json.load(open('/tmp/claude-0/-home-user/0cabdeea-4c4e-552d-b4e1-e4352e3f0cc0/scratchpad/at.json'))
HTML = open(sys.argv[1]).read()
USED = set(re.findall(r"fld[A-Za-z0-9]{14}", HTML))
T = {t['id']: t for t in AT['tables']}

def kind(f):
    t = f['type']
    if t in ('formula', 'rollup', 'lookup', 'count'):
        return 'ro'
    if t in ('autoNumber', 'createdTime'):
        return 'ro'
    return {'number': 'num', 'currency': 'num', 'percent': 'num', 'checkbox': 'bool', 'date': 'date',
            'dateTime': 'dt', 'multipleSelects': 'multi', 'multipleRecordLinks': 'link',
            'multipleAttachments': 'att'}.get(t, 'text')

FC = {
 'Numero Dossier':'numero_dossier','Agent Crédit':'agent_credit','Agent Epargne':'agent_epargne','Numero Epargne':'numero_epargne',
 'Compte Epargne':'id_compte_epargne','Nom':'nom','ID Formulaire':'id_formulaire','Zone':'zone','Lieu de travail':'lieu_travail',
 'Type de crédit':'type_credit','Montant du crédit':'montant_demande','Date Soumission':'created_at','Date Demande':'date_demande','ID':'numero',
 'Mention Credit':'mention_credit','Liste Document':'liste_documents','Document de domicile':'document_domicile',
 'New Contrat Credit':'id_contrat','Compte Credit':'id_compte_credit','New Contrat Credit 2':'id_contrat','Dossier Client | Formulaire':'id_dossier_client',
 'Prenom':'prenom','Nom Complet':'nom_complet','Type demande':'type_demande','Contrôle DS':'controle_ds','Étape Analyse':'etape',
 'Date remise formulaire':'date_remise','Date retour réel':'date_retour','AM assigné':'am_assigne','Date début analyse AM':'date_debut_am',
 'Décision AM':'decision_am','Date décision AM':'date_decision_am','Commentaire AM':'commentaire_am','Date envoi Manager':'date_envoi_manager',
 'Décision Manager':'decision_manager','Date décision Manager':'date_decision_manager','Commentaire Manager':'commentaire_manager',
 'Documents reçus':'documents_recus','Date retour attendue':'date_retour_attendue','Deadline AM':'deadline_am','Deadline Manager':'deadline_manager',
 'Statut Délai':'statut_delai','Respect délais':'respect_delais','Retour enregistré par':'retour_par','Motif blocage':'motif_blocage',
 'Observation blocage':'observation_blocage','Date blocage':'date_blocage','Statut Suivi':'statut_suivi','Remis par':'remis_par',
 'Date levée blocage':'date_levee_blocage','Jours utilisés':'jours_utilises','Retard (jours)':'retard_jours','Raison du retard':'raison_retard',
 'Conformité OK':'conformite_ok','Conformité (%)':'conformite_pct','Taux fonds garantie (%)':'taux_fonds_garantie',
 'Source fonds garantie':'source_fonds_garantie','Montant fonds garantie requis':'montant_fdg_requis','Montant accordé (AM)':'montant_accorde',
 'Durée (mois) (AM)':'duree_mois',"Taux d'intérêt (%) (AM)":'taux_interet','Paiement par jour (AM)':'paiement_jour',
 'Nombre de versements (AM)':'nombre_versements','Montant total à rembourser (AM)':'montant_total_am','Score crédit /100':'score_credit',
 'Statut AM':'statut_am','Jours AM utilisés':'jours_am_utilises','Retard AM (jours)':'retard_am_jours',
 'Lettre de validation générée le':'lettre_generee_le','Lettre générée par':'lettre_generee_par','Lettre statut':'lettre_statut',
 "Lettre remise à l'agent le":'lettre_remise_le','Lettre retournée le':'lettre_retournee_le','Lettre motif non signature':'lettre_motif_non_signature',
 'RDV décaissement':'rdv_decaissement','Lettre RDV générée le':'lettre_rdv_le','Autorisation admin RDV':'autorisation_admin_rdv',
 'Documents scannés':'documents_scannes','Réf. lettre AR':'ref_lettre_ar','Lettre AR générée le':'lettre_ar_le','Réf. lettre LV':'ref_lettre_lv',
 'Réf. lettre RD':'ref_lettre_rd','Données lettres':'donnees_lettres','Statut RDV':'statut_rdv','Note RDV':'note_rdv','Finance étape':'finance_etape',
 'Réf. lettre LC':'ref_lettre_lc','Réf. ordre OD':'ref_ordre_od','Décision finance':'decision_finance','Date décaissement prévue':'date_decaissement',
 'Données finance':'donnees_finance','Documents détail':'documents_detail','Réf. contrat CT':'ref_contrat_ct','Statut contrat':'statut_contrat',
 'Données contrat':'donnees_contrat','Dernier versement AM':'dernier_versement','Délai ajournement AM':'delai_ajournement_am',
 'Délai retour Manager':'delai_retour_manager','Compte FDG (correction)':'compte_fdg_correction','Réf. lettre PM':'ref_lettre_pm',
 'Délai conformité AM (jours)':'delai_conformite_am','Date limite conformité':'date_limite_conformite',
}
USERS = {'Identifiant':'identifiant','Nom complet':'nom_complet','Rôle':'role','AM':'equipe_am','Mot de passe (hash)':None,
         'Actif':'actif','Doit changer mot de passe':'doit_changer_mdp','Dernière connexion':'derniere_connexion'}
VAL = {'OK':None,'Clé':'cle','Dossier':'id_formulaire','N°':'num_etape','Étape':'etape','Statut':'statut','Critères vérifiés':'criteres_verifies',
       'Date vérification':'date_verification','Vérifié par':'verifie_par','Commentaire':'commentaire','Montant':'montant','Téléphone confirmé':'telephone_confirme'}
PAR = {'Clé':'cle','Valeur':'valeur','Modifié par':'modifie_par'}
DSM = {'Compte Credit':'credits','Nom Complet | Formulaire':'nom_formulaire','Formulaire Credit':'formulaires','Zone | Formulaire':'zone_formulaire',
       'Nom Definitif':'nom','Zone Definitve':'zone','Lieu de travail (Formulaire)':'lieu_formulaire','Lieu de travail Def':'lieu_travail',
       'Clé Client':'cle_client','N° DS':'num_ds','Statut Dossier':'statut_dossier'}
CT = {'Numéro du crédit':'numero_credit','Piece Identification':'piece_identification','Numero Identification':'numero_identification',
      'Date Naissance':'date_naissance','Sexe':'sexe','Adresse':'adresse','Numéro de téléphone':'telephone','Numéro de compte épargne':'numero_epargne',
      'Montant du crédit - en chiffres':'montant','Montant du crédit - en lettres':'montant_lettres','Durée du crédit':'duree_mois',
      'Date de début du crédit':'date_debut',"Date d'échéance du crédit":'date_echeance','Modalités de remboursement':'modalites',
      'Objet du crédit':'objet','Montant final du crédit':'montant_final','Fonds de garantie':'fonds_garantie','Frais et pénalités':'penalites',
      'Nom complet du témoin':'temoin_nom',"Piece d'identification du témoin":'temoin_piece',"Numéro d'identification du témoin":'temoin_numero',
      'Adresse du témoin':'temoin_adresse','Nombre de jour de congé':'jours_conge','Agent Crédit':'agent_credit','Numéro de Formulaire':'numero_formulaire',
      'Liaison Forms':'id_formulaire','Agent Epargne':'agent_epargne','Frais Dossier':'frais_dossier','Type Credit':'type_credit',
      'Paiement par jour':'paiement_jour','Taux interet':'taux_interet','Nom du client':'nom_client','Prenom du client':'prenom_client',
      'Compte Epargne':'id_compte_epargne','Dossier Client':'id_dossier_client','Numero Dossier Client':'numero_dossier_client','Suivi Remboursement':'suivi_remboursement'}
CC = {'ID Credit':'id_credit','Nom Complet':'nom_complet','Timestamp':'created_at','Adresse entreprise':'adresse_entreprise',
      'Numero compte epargne':'numero_epargne','Type Crédit':'type_credit','Montant pret':'montant_pret',"Taux d'interet":'taux_interet',
      'Duree du credit (mois)':'duree_credit_mois','Paiement par jour':'paiement_journalier','Montant Final':'montant_final',
      'Nbre de versement':'nb_versements','Restant':'restant','Credit avorte':None,'Date de debut':'date_debut','Date de fin':'date_fin',
      'Dernier Versement':'dernier_versement','Collecteur Par Defaut (Credit)':None,'Remboursement Definitif':'remboursement',
      'Versement Definitif':'remboursement','Dossier Client':'dossiers_clients','Statut creances':'statut_creances','Agent Recouvrement':None}
RISK = {'Numero Dossier':'numero_dossier','Dossier':'id_formulaire','Risques identifiés':'risques_identifies',
        'Niveau de risque global':'niveau_global','Synthèse / recommandation':'synthese','Évalué par':'evalue_par','Date évaluation':'date_evaluation',
        'R7 Autres - Précision':'r7_precision','R8 Moyens de contact - Concerne':'r8_concerne'}
for i, k in enumerate(['Incapacité','Géographique','Saisonnalité','Surendettement','Utilisation','Incohérence','Autres','Moyens de contact'], 1):
    RISK[f'R{i} {k} - Explication'] = f'r{i}_explication'; RISK[f'R{i} {k} - Plan de gestion'] = f'r{i}_plan'
RC = {'ID Rapport':'id_rapport','N°':'numero','Dossier':'id_formulaire','Numero Dossier':'numero_dossier','Client':'client',
      'N° Compte Epargne':'numero_epargne','Agent recouvrement':'agent_recouvrement','Statut':'statut','Date création':'date_creation',
      'Créé par':'cree_par','Date limite':'date_limite','ID Credit précédent':'id_credit_precedent','Montant prêt':'montant_pret',
      'Montant total à rembourser':'montant_total','Montant remboursé':'montant_rembourse','Solde restant':'solde_restant',
      'Date début crédit':'date_debut_credit','Date fin crédit':'date_fin_credit','Date dernier versement':'date_dernier_versement',
      'Statut créances':'statut_creances','Nombre de retards':'nombre_retards','Comportement de paiement':'comportement_paiement',
      'Observations agent':'observations_agent','Recommandation agent':'recommandation_agent','Attestation remboursement complet':'attestation_remboursement',
      'Date attestation':'date_attestation','Attesté par':'atteste_par','Rempli le':'rempli_le','Vérification AM':'verification_am',
      'Observation AM':'observation_am','Vérifié par':'verifie_par','Date vérification':'date_verification','Données rapport':'donnees_rapport',
      'Score historique':'score_historique','Mode de clôture':'mode_cloture','Recommandation renouvellement':'recommandation_renouvellement',
      'Vérifié par (AM)':'verifie_par_am','Date vérification AM':'date_verification_am','Observation Manager':'observation_manager',
      'Modèle de rapport':'modele_rapport'}

def score_col(name):
    m = re.match(r'^([ASFM][1-4])( pts| justificatif|)\b', name)
    if m and not name.startswith('Stock') and not name.startswith('SCORE'):
        base = m.group(1).lower(); suf = m.group(2)
        if name.endswith('justificatif'): return base + '_justif'
        if name.endswith('pts'): return base + '_pts'
        return base
    return {'Numéro Dossier':'numero_dossier','Dossier':'id_formulaire','Personne de référence':'personne_reference',
     'Stock type de marchandises':'stock_type','Stock valeur estimée':'stock_valeur','Stock rotation':'stock_rotation',
     'Stock périssabilité':'stock_perissabilite','Stock adapté à la demande':'stock_adapte','Stock appréciation':'stock_appreciation',
     'Stock justificatif':'stock_justif','Ventes journalières':'ventes_jour','Dépenses journalières':'depenses_jour','Bénéfice journalier':'benefice_jour',
     'Revenu mensuel':'revenu_mensuel','Dépenses du ménage':'depenses_menage',"Base d'analyse (revenu − ménage)":'base_analyse',
     'Garantie type':'garantie_type','Garantie pts':'garantie_pts','Garantie justificatif':'garantie_justif','Risques identifiés':'risques_identifies',
     'Risques justificatif':'risques_justif','Commentaire':'commentaire','Évalué par':'evalue_par','Date évaluation':'date_evaluation',
     'Sous-total Activité /20':'total_activite','Sous-total Stabilité /20':'total_stabilite','Sous-total Financier /25':'total_financier',
     'Sous-total Moralité /20':'total_moralite','SCORE TOTAL /100':'score_total','Décision selon le score':'decision_selon_score',
     'Taux capacité de remboursement (%)':'taux_capacite','Capacité mensuelle de remboursement':'capacite_mensuelle',
     'Montant recommandé':'montant_recommande','Durée recommandée (mois)':'duree_recommandee','Modalité':'modalite','Modalité précision':'modalite_precision',
     'Avis AM - activité':'avis_am','Avis AM justificatif':'avis_am_justif','Décision AM (grille)':'decision_am_grille',
     'Décision AM justificatif':'decision_am_justif','Capacité quotidienne de remboursement':'capacite_jour'}.get(name)

SPEC = [  # (table id, nom, vue lecture, table écriture, dict nom->col, ordre de tri par défaut)
 ('tblN5JwXYJJZhbr7f','Formulaire Credit','v_formulaires','formulaires',FC),
 ('tbljABvHisDJWrKgM','Utilisateurs Suivi','utilisateurs','utilisateurs',USERS),
 ('tblknADveJL6MTIVk','Validation Conformité','v_validations','validations',VAL),
 ('tbloBxMIOCLPm1qV4','Scoring Crédit','v_scorings','scorings',None),
 ('tblk1FwcKewxxlsNT','Risques Crédit','risques','risques',RISK),
 ('tblAq8ePKGohxfz6L','Rapports Clôture','rapports_cloture','rapports_cloture',RC),
 ('tblOzcArf5qk17aok','Paramètres Suivi','parametres','parametres',PAR),
 ('tblXy4bz6MaCuddWe','Dossier Client','v_dossiers_clients','dossiers_clients',DSM),
 ('tblsYfHc8ZUW42DLy','Contrat Credit','contrats','contrats',CT),
 ('tblLglKu4OyEAg4t0','Compte Credit','ext_comptes_credit',None,CC),
]
RO_COLS = {'nom_complet','date_retour_attendue','deadline_am','deadline_manager','statut_delai','respect_delais','statut_suivi',
  'jours_utilises','retard_jours','conformite_ok','conformite_pct','montant_fdg_requis','montant_total_am','score_credit','statut_am',
  'jours_am_utilises','retard_am_jours','numero','created_at','numero_dossier_ro','etape_ro','credits','formulaires','num_ds','cle_client',
  'statut_dossier','total_activite','total_stabilite','total_financier','total_moralite','score_total','decision_selon_score',
  'capacite_mensuelle','capacite_jour'}

out = {}
missing = []
for tid, tname, rd, wr, M in SPEC:
    fields = []
    for f in T[tid]['fields']:
        if f['id'] not in USED and not (M and f['name'] in M):
            continue
        col = score_col(f['name']) if M is None else M.get(f['name'], '??')
        if col == '??' or (M is None and col is None):
            missing.append((tname, f['name'])); continue
        if col is None:
            continue
        k = kind(f)
        if k == 'ro' or col in RO_COLS or wr is None:
            ro = True
        else:
            ro = False
        base = {'number':'num','currency':'num','checkbox':'bool','date':'date','dateTime':'dt','createdTime':'dt','autoNumber':'num',
                'multipleSelects':'multi','multipleRecordLinks':'link','multipleAttachments':'att'}.get(f['type'],'text')
        if f['type'] in ('formula','rollup'):
            base = 'num' if col in ('conformite_ok','conformite_pct','montant_fdg_requis','montant_total_am','score_credit','jours_utilises','retard_jours',
                                    'jours_am_utilises','retard_am_jours','total_activite','total_stabilite','total_financier','total_moralite',
                                    'score_total','capacite_mensuelle','capacite_jour','remboursement','restant','nb_versements','montant_final') else 'text'
            if col in ('date_debut','date_fin'): base = 'date'
            if col in ('credits','formulaires','dossiers_clients'): base = 'link'
        if f['type'] == 'rollup' and col == 'dernier_versement': base = 'date'
        if tname == 'Validation Conformité' and col in ('etape','cle'): ro = True
        fields.append([f['id'], f['name'], col, base, 1 if ro else 0])
    out[tid] = {'name': tname, 'read': rd, 'write': wr, 'fields': fields}

# Table « Compte Epargne » (copie dans la base Crédit) -> comptes épargne
out['tblyFXV5zkeBd7joJ'] = {'name':'Compte Epargne','read':'ext_comptes_epargne','write':None,'fields':[
  ['_ce_num','N° Compte','no_compte','text',1],['_ce_nom','Nom Complet','nom_complet','text',1]]}

json.dump(out, open('/home/user/kredi/build/mapping.json','w'), ensure_ascii=False, indent=0)
print('missing', missing)
for tid, t in out.items():
    print(t['name'], len(t['fields']), 'rw' if t['write'] else 'ro')
