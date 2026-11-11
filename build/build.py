# Construit suivi_analyse_credit_supabase.html à partir du HTML Airtable v1.52.1
import json, re, sys
SRC = sys.argv[1]
OUT = sys.argv[2]
UMD = '/tmp/claude-0/-home-user/0cabdeea-4c4e-552d-b4e1-e4352e3f0cc0/scratchpad/sbjs/package/dist/umd/supabase.js'
h = open(SRC, encoding='utf-8').read()
n_patch = 0

def sub(old, new, count=1, regex=False):
    """remplace exactement `count` occurrence(s), sinon échoue"""
    global h, n_patch
    found = len(re.findall(old, h, re.S)) if regex else h.count(old)
    if found != count:
        raise SystemExit(f'PATCH échoue ({found} trouvé(s), {count} attendu(s)) : {old[:90]!r}')
    h = re.sub(old, lambda m: new, h, flags=re.S) if regex else h.replace(old, new)
    n_patch += 1

# ---------- 1. bibliothèque Supabase + adaptateur, juste avant le script principal ----------
mapping = json.load(open('mapping.json', encoding='utf-8'))
adapter = open('sb_adapter.js', encoding='utf-8').read().replace('/*MAPPING*/{}', json.dumps(mapping, ensure_ascii=False))
umd = open(UMD, encoding='utf-8').read().replace('</script', '<\\/script').replace('if(!e)throw new Error("Automatic publicPath is not supported in this browser");', 'if(!e)e=location.href;')
sub('<div class="toast" id="toast"></div>\n\n<script>',
    '<div class="toast" id="toast"></div>\n\n<script>/* @supabase/supabase-js 2.45.4 (MIT) */\n' + umd + '\n</script>\n<script>\n' + adapter + '\n</script>\n<script>')

# ---------- 2. toutes les requêtes Airtable passent par Supabase ----------
sub("const DEMO=(()=>{try{return localStorage.getItem('sa_demo')==='1'}catch(e){return false}})();", "const DEMO=false; // mode démo Airtable désactivé : données dans Supabase")
sub("if(DEMO){window.fetch=function(url,opt){if(typeof url==='string'&&url.startsWith('https://api.airtable.com/'))return demoFetch(url,opt);return _realFetch(url,opt)}}",
    "window.fetch=function(url,opt){if(typeof url==='string'&&url.startsWith('https://api.airtable.com/'))return sbFetch(url,opt);return _realFetch(url,opt)};")
sub(r"async function scanUploadOne\(recId,file,filename\)\{.*?return j\}", "async function scanUploadOne(recId,file,filename){return sbUpload(recId,file,filename)}", regex=True)
sub("const RG_DEFAULT_TX='2026-04=appMFNt9Y2eMTGyzT\\n2026-05=appxHLtGPkWgL4yWr\\n2026-06=appbpMBHC78d5IpWi\\n2026-07=appSRLFryIKgxEHML\\n2026-08=appdIqd3KnhqHyRa9\\n2026-09=appQv5AygXltuTvBa\\n2026-10=app9e6Rtu51xs7mgC';",
    "const RG_DEFAULT_TX=''; // mois détectés dans Supabase (transactions_epargne)")
sub("try{const saved=JSON.parse(ls.get('sa_txbases')||'{}');Object.assign(found,saved)}catch(e){}", "")

# ---------- 3. connexion : Supabase Auth ----------
sub(r"async function login\(\)\{.*?\n\}\nfunction logout\(\)\{user=null;ss\.del\('sa_user'\);recs=\[\];location\.reload\(\)\}",
r"""async function login(){
  const l=g('l-user').value.trim(),p=g('l-pass').value;
  if(!l||!p){g('l-info').textContent='Identifiant et mot de passe requis';return}
  g('l-go').disabled=true;g('l-info').textContent='Vérification…';
  try{
    const {data,error}=await SB.auth.signInWithPassword({email:sbEmail(l),password:p});
    if(error){g('l-info').textContent='Identifiant ou mot de passe incorrect';g('l-go').disabled=false;return}
    const {data:u,error:e2}=await SB.from('utilisateurs').select('*').eq('user_id',data.user.id).maybeSingle();
    if(e2)throw new Error(e2.message);
    if(!u||!u.actif){await SB.auth.signOut();g('l-info').textContent=u?'Compte désactivé — contactez l\'Admin':'Ce compte n\'a pas accès au suivi crédit';g('l-go').disabled=false;return}
    user={id:u.user_id,login:u.identifiant,name:u.nom_complet||u.identifiant,role:u.role,am:u.equipe_am||'*',mustChange:!!u.doit_changer_mdp};
    ss.set('sa_user',JSON.stringify(user));
    SB.rpc('marquer_connexion',{p_mdp_change:false}).then(()=>{},()=>{});
    g('l-pass').value='';enterApp();
  }catch(e){g('l-info').textContent='Erreur : '+e.message}
  g('l-go').disabled=false;
}
async function logout(){try{await SB.auth.signOut()}catch(e){}user=null;ss.del('sa_user');recs=[];location.reload()}""", regex=True)

sub(r"    const r=await findUser\(user\.login\);\n    if\(!r\|\|r\.fields\[U\.hash\]!==await pwHash\(user\.login,o\)\)\{toast\('Mot de passe actuel incorrect'\);return\}\n    await api\(.*?USERS_TABLE\);",
r"""    const {data:okOld,error:e1}=await SB.rpc('verifier_mon_mdp',{p_mdp:o});if(e1)throw new Error(e1.message);
    if(!okOld){toast('Mot de passe actuel incorrect');return}
    const {error:e2}=await SB.auth.updateUser({password:n});if(e2)throw new Error(e2.message);
    await SB.rpc('marquer_connexion',{p_mdp_change:true});""", regex=True)

sub(r"  const fields=\{\[U\.login\]:l,\[U\.name\]:n\|\|l,\[U\.role\]:role,\[U\.hash\]:await pwHash\(l,pw\),\[U\.actif\]:true,\[U\.mustChange\]:true\};\n  if\(role==='Assistant Manager'\)fields\[U\.am\]=am;\n  try\{await api\(.*?USERS_TABLE\);",
r"""  try{const {error}=await SB.rpc('admin_creer_utilisateur',{p_identifiant:l,p_nom:n||l,p_role:role,p_equipe_am:role==='Assistant Manager'?am:null,p_mdp:pw});if(error)throw new Error(error.message);""", regex=True)

sub(r"  try\{await api\('',\{method:'PATCH',body:JSON\.stringify\(\{records:\[\{id,fields:\{\[U\.hash\]:await pwHash\(r\.fields\[U\.login\],pw\),\[U\.mustChange\]:true\}\}\]\}\)\},USERS_TABLE\);",
r"""  try{const {error}=await SB.rpc('admin_reinit_mdp',{p_user:id,p_mdp:pw});if(error)throw new Error(error.message);""", regex=True)

sub(r"try\{const admins=await api\(`\?returnFieldsByFieldId=true&filterByFormula=\$\{encodeURIComponent\(`AND\(\{Rôle\}='Admin',\{Actif\}=1\)`\)\}`,\{\},USERS_TABLE\);let okA=null;for\(const a of admins\.records\)\{const h=await pwHash\(a\.fields\[U\.login\]\|\|'',pw\);if\(h===a\.fields\[U\.hash\]\)\{okA=a;break\}\}\n      if\(!okA\)\{toast\('Mot de passe admin incorrect — autorisation refusée'\);return\}auth=`Autorisé par \$\{okA\.fields\[U\.name\]\|\|okA\.fields\[U\.login\]\}",
r"""try{const {data:okA,error:eA}=await SB.rpc('verifier_mdp_admin',{p_mdp:pw});if(eA)throw new Error(eA.message);
      if(!okA){toast('Mot de passe admin incorrect — autorisation refusée');return}auth=`Autorisé par ${okA}""", regex=True)

# démarrage : plus de jeton Airtable, la session Supabase fait foi
sub("if(cfg.token==='DEMO-TOKEN'||!/^pat/.test(cfg.token||'')){cfg.token='';ls.set('sa_cfg',JSON.stringify(cfg))} // jeton invalide laissé par une ancienne version démo",
    "cfg={token:'SUPABASE',base:DEFAULT_BASE,table:DEFAULT_TABLE}; // connexion Supabase (plus de jeton Airtable)")
sub("  if(user)enterApp();\n", "  if(user)SB.auth.getSession().then(({data})=>{if(data&&data.session)enterApp();else{user=null;ss.del('sa_user')}});\n")
sub(r"function updTokStatus\(\)\{const e=g\('l-tok'\);if\(!e\)return;.*?\}\n", "function updTokStatus(){const e=g('l-tok');if(!e)return;e.textContent='Base de données : Supabase (Debloke Test)';e.style.color='var(--ok)'}\n", regex=True)

# ---------- 4. numéros de compte Supabase (plus seulement A-BSI- / A-BSG-) ----------
sub("if(v.length<6||!/^A-BS[IG]-/.test(v)){box.classList.add('hidden');return}", "if(v.length<3){box.classList.add('hidden');return}")
sub("if(v.startsWith('A-BSG-')){const r=await fetch(", "if(false){const r=await fetch(")
sub("""  if(!/^A-BS[IG]-/.test(ep)){info.innerHTML='<span style="color:var(--bad)">Format attendu : A-BSI-… (épargne) ou A-BSG-… (Grandon)</span>';return}\n""", "")
sub("    if(ep.startsWith('A-BSG-')){\n", "    if(false){\n")
sub("  if(!/^A-BS[IG]-/i.test(ep)){toast('Le N° de compte doit commencer par A-BSI- (épargne) ou A-BSG- (Grandon)');g('n-epargne').focus();return}\n", "")
sub("${ep.startsWith('A-BSG-')?'compte Grandon':'compte épargne'}", "compte épargne / Grandon")
sub('placeholder="A-BSI-… ou A-BSG-…"', 'placeholder="N° de compte épargne ou Grandon"')

# ---------- 5. textes : Airtable → Supabase ----------
sub("un dossier <b>DS-</b> sera créé automatiquement par Airtable", "un dossier <b>DS-</b> est créé automatiquement par le système")
sub("⏳ Airtable crée le dossier DS… (quelques secondes)", "⏳ création du dossier DS… (quelques secondes)")
sub("toast('Erreur Airtable : '+e.message)", "toast('Erreur base de données : '+e.message)", count=3)
sub("<h3>Connexion Airtable</h3>", "<h3>Connexion à la base de données</h3>")
sub(r'<p class="muted">Créez un <b>Personal Access Token</b>.*?</p>', '<p class="muted">L\'application est connectée à <b>Supabase</b> (projet Debloke Test, schéma <code>kredi</code>). Aucun jeton n\'est nécessaire : chaque utilisateur se connecte avec son identifiant et son mot de passe.</p>', regex=True)
sub("<title>Suivi Analyse Crédit v1.52.1</title>", "<title>Suivi Analyse Crédit v1.52.1 · Supabase</title>")

open(OUT, 'w', encoding='utf-8').write(h)
print(f'{n_patch} patches appliqués → {OUT} ({len(h)//1024} Ko)')
