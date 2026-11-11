/* =====================================================================
   ADAPTATEUR SUPABASE  —  remplace Airtable sans toucher à la logique de l'app.
   Toutes les requêtes « https://api.airtable.com/v0/... » sont interceptées et
   servies depuis le schéma Supabase « kredi » (projet Debloke Test).
   ===================================================================== */
const SB_URL='https://riutfmqffpffniutbhue.supabase.co';
const SB_KEY='sb_publishable_p8aTqDgmHm7XvpkEjk7LiQ_X5QgwbfZ';
const SB_BUCKET='kredi-documents';
const SB=supabase.createClient(SB_URL,SB_KEY,{db:{schema:'kredi'},auth:{persistSession:true,autoRefreshToken:true,storageKey:'kredi-auth'}});
const sbEmail=l=>{l=String(l||'').trim().toLowerCase();return l.includes('@')?l:l+'@kredi.bwatsekrem.ht'};

/* ---------- registre des tables : [id champ Airtable, nom, colonne, type, lecture seule] ---------- */
const SB_MAP=/*MAPPING*/{};
const SB_EXT={ // tables des « autres bases » (épargne, frais, fonds de garantie, transactions)
  tblaf7CAAbVh07UfB:{name:'Compte Epargne',read:'ext_comptes_epargne',write:null,fields:[
    ['fld55tLXWpucA7pxL','Date de naissance','date_naissance','date',1],['fldRXoP4IRt33igPe','NIF','nif_cin','text',1],
    ['fld1kfnfTCyA3C9El','Sexe','sexe','text',1],['fldyEnluQH3TecBbd','Adresse ','adresse','text',1],
    ['fld38k4GJ0jbXfqty','Numéro de Téléphone','telephone','text',1],['fldrlYzp01xN6fBn2','Activité','activite','text',1],
    ['fldmnozFeBErpuTVt','N° Compte','no_compte','text',1],['fldeP848gYaFGHikU','Nom Complet','nom_complet','text',1],
    ['fld20BSxxFywAMXYs','Solde Definitif','solde','num',1],['fld67HvS1Fprxmnx8','Collecteur par défaut','collecteur','text',1],
    ['fldR6qHNXPzbevD2l','Collecteur','collecteur','text',1],['fldFSaLlylmmqa5do','Bloqué','bloque','bool',1],
    ['_ep_nom','Nom','nom','text',1],['_ep_prenom','Prenom','prenom','text',1],['_ep_pseudo','Pseudo','pseudo','text',1],
    ['_ep_zone','Zone','zone','text',1],['_ep_plan','Plan ','plan_journalier','num',1],['_ep_ts','Timestamp','created_at','dt',1],
    ['_ep_cat','categorie compte','categorie','text',1],['_ep_lieu','Lieu de Travail','lieu_de_travail','text',1],['_ep_occ','Occupation','occupation','text',1]]},
  tblS6gYpwbs3jjUy0:{name:'Gestion Frais Dossier',read:'frais_dossier',write:'frais_dossier',fields:[
    ['fldPS4BQiNHZaMaWW','Numero Dossier','numero_dossier','text',0],['fldCo3DKFhPkmVII6','Statut','statut','text',0],
    ['fldVAEyxlYM7gSV2z','Montant payé','montant_paye','num',0],['fldROtREvwU4zHVPl','Montant','montant','num',0],
    ['fldCGbhTM1IhvQYPD','Date','date_paiement','date',0],['fldURgWWewB0XE7sT','N° Compte Epargne','numero_epargne','text',0]]},
  tblUJFKGcnRbjqRf4:{name:'Fonds Garantie',read:'ext_fonds_garantie',write:null,fields:[
    ['fldHMW4ZRMUFnKFHs','ID Compte','id_compte','text',1],['fldjFtGAtJi2qkYkA','Solde','solde','num',1],
    ['fld2SiUkjrtozfWY0','Compte Epargne','comptes_epargne','multi',1],['flda3CoBiYv5ep55G','Nom','nom','text',1],['fld4IDdLwgND3VWf7','Prénom','prenom','text',1]]},
  _tx:{name:'Transactions',read:'ext_transactions_epargne',write:null,fields:[
    ['_tx_d','Date','date','date',1],['_tx_c','Compte','compte','text',1],['_tx_col','Collecteur','collecteur','text',1],
    ['_tx_dep','Depot','depot','num',1],['_tx_ret','Retrait','retrait','num',1]]}
};
const SB_PK={utilisateurs:'user_id'};
const SB_AUTO_STEPS=[1,7,15,17,18];
const SB_MOIS=['jan','fev','mars','avr','mai','juin','juil','aout','sept','oct','nov','dec'];
(function(){for(const t of Object.values({...SB_MAP,...SB_EXT})){t.byId={};t.byName={};t.fields=t.fields.map(f=>({id:f[0],name:f[1],col:f[2],type:f[3],ro:!!f[4]}));for(const o of t.fields){t.byId[o.id]=o;if(!t.byName[o.name])t.byName[o.name]=o}}})();

function sbResolve(base,table){
  table=decodeURIComponent(table||'');
  if(/^sbTX_/.test(base)||table==='Transactions')return {t:SB_EXT._tx,mois:/^sbTX_/.test(base)?base.slice(5):'__none__'};
  if(SB_MAP[table])return {t:SB_MAP[table]};
  if(SB_EXT[table])return {t:SB_EXT[table]};
  if(table==='Compte Epargne'&&base===EXT.epargne.base)return {t:SB_EXT.tblaf7CAAbVh07UfB};
  for(const t of [...Object.values(SB_MAP),...Object.values(SB_EXT)])if(t.name===table)return {t};
  return null;
}
const sbPk=t=>SB_PK[t.write||t.read]||'id';

/* ---------- conversions ---------- */
function sbToDb(f,v){
  if(v&&typeof v==='object'&&!Array.isArray(v)&&'name'in v)v=v.name;
  switch(f.type){
    case 'num': return v===''||v==null||isNaN(+v)?null:+v;
    case 'bool': return !!v;
    case 'date': return v?String(v).slice(0,10):null;
    case 'dt': return v||null;
    case 'multi': return v==null||v===''?[]:(Array.isArray(v)?v.map(x=>x&&x.name||x):String(v).split(',').map(s=>s.trim()).filter(Boolean));
    case 'link': {const a=Array.isArray(v)?v:(v?[v]:[]);const x=a[0];return x?(x.id||x):null}
    default: return v==null||v===''?null:String(v);
  }
}
function sbFromDb(f,v,urls){
  if(v==null||v===''||v===false)return undefined;
  if(Array.isArray(v)&&!v.length)return undefined;
  switch(f.type){
    case 'num': return +v;
    case 'link': return Array.isArray(v)?v.filter(Boolean):[v];
    case 'att': return (Array.isArray(v)?v:[]).map(a=>{const u=(urls&&urls[a.path])||'';return {id:a.id,url:u,filename:a.filename,type:a.type,size:a.size,thumbnails:{small:{url:u},large:{url:u},full:{url:u}}}});
    case 'date': return String(v).slice(0,10);
    default: return v;
  }
}
function sbRecord(t,row,byId,urls){
  const fields={};
  for(const f of t.fields){if(byId&&f.id.startsWith('_'))continue;const v=sbFromDb(f,row[f.col],urls);if(v!==undefined)fields[byId?f.id:f.name]=v}
  return {id:String(row[sbPk(t)]),createdTime:row.created_at||row.modifie_le||new Date(0).toISOString(),fields};
}
async function sbSignUrls(t,rows){
  const att=t.fields.filter(f=>f.type==='att');if(!att.length)return null;
  const paths=[];rows.forEach(r=>att.forEach(f=>(r[f.col]||[]).forEach(a=>a&&a.path&&paths.push(a.path))));
  if(!paths.length)return {};
  const {data}=await SB.storage.from(SB_BUCKET).createSignedUrls([...new Set(paths)],3600);
  const m={};(data||[]).forEach(x=>{if(x.signedUrl)m[x.path]=x.signedUrl});return m;
}

/* ---------- formules Airtable (sous-ensemble utilisé par l'app) ---------- */
function sbTok(s){const T=[];let i=0;
  while(i<s.length){const c=s[i];
    if(/\s/.test(c)){i++;continue}
    if(c==="'"||c==='"'){let j=i+1,o='';while(j<s.length&&s[j]!==c){if(s[j]==='\\'&&j+1<s.length){o+=s[j+1];j+=2;continue}o+=s[j++]}T.push({k:'s',v:o});i=j+1;continue}
    if(c==='{'){const j=s.indexOf('}',i);T.push({k:'f',v:s.slice(i+1,j)});i=j+1;continue}
    if(/[0-9.]/.test(c)){let j=i;while(j<s.length&&/[0-9.]/.test(s[j]))j++;T.push({k:'n',v:+s.slice(i,j)});i=j;continue}
    if(/[A-Za-z_]/.test(c)){let j=i;while(j<s.length&&/[A-Za-z_0-9]/.test(s[j]))j++;T.push({k:'id',v:s.slice(i,j).toUpperCase()});i=j;continue}
    const two=s.slice(i,i+2);if(['!=','>=','<='].includes(two)){T.push({k:'op',v:two});i+=2;continue}
    T.push({k:'op',v:c});i++}
  return T}
function sbParse(src){const T=sbTok(src);let p=0;const peek=()=>T[p],eat=v=>{const t=T[p];if(v&&(!t||t.v!==v))throw new Error('Formule non comprise : '+src);p++;return t};
  const PREC={'=':1,'!=':1,'>':1,'<':1,'>=':1,'<=':1,'&':2,'+':3,'-':3,'*':4,'/':4};
  function prim(){const t=eat();
    if(t.k==='s'||t.k==='n')return {k:'lit',v:t.v};
    if(t.k==='f')return {k:'fld',v:t.v};
    if(t.k==='op'&&t.v==='('){const e=expr(0);eat(')');return e}
    if(t.k==='op'&&t.v==='-')return {k:'neg',e:prim()};
    if(t.k==='id'){if(t.v==='TRUE')return {k:'lit',v:true};if(t.v==='FALSE')return {k:'lit',v:false};
      eat('(');const a=[];if(peek()&&peek().v!==')'){a.push(expr(0));while(peek()&&peek().v===','){eat(',');a.push(expr(0))}}eat(')');return {k:'fn',n:t.v,a}}
    throw new Error('Formule non comprise : '+src)}
  function expr(minP){let l=prim();while(peek()&&peek().k==="op"&&PREC[peek().v]>minP){const op=eat().v;const r=expr(PREC[op]);l={k:'bin',op,l,r}}return l}
  const e=expr(0);if(p<T.length)throw new Error('Formule non comprise : '+src);return e}
const sbStr=v=>v==null?'':Array.isArray(v)?v.join(', '):typeof v==='boolean'?(v?'1':''):String(v);
const sbDate=v=>{if(v instanceof Date)return v;if(!v)return null;const s=String(v);return new Date(/^\d{4}-\d{2}-\d{2}$/.test(s)?s+'T00:00:00':s)};
function sbEval(n,ctx){
  switch(n.k){
    case 'lit':return n.v;
    case 'neg':return -sbEval(n.e,ctx);
    case 'fld':{const f=ctx.t.byName[n.v];if(!f)return '';const v=ctx.row[f.col];if(v==null)return '';if(f.type==='bool')return v?1:0;if(Array.isArray(v))return v.join(', ');return v}
    case 'bin':{const a=sbEval(n.l,ctx),b=sbEval(n.r,ctx);
      switch(n.op){case '&':return sbStr(a)+sbStr(b);case '+':return (+a||0)+(+b||0);case '-':return (+a||0)-(+b||0);case '*':return (+a||0)*(+b||0);case '/':return (+a||0)/(+b||1);
        case '=':return sbEq(a,b);case '!=':return !sbEq(a,b);
        case '>':return sbCmp(a,b)>0;case '<':return sbCmp(a,b)<0;case '>=':return sbCmp(a,b)>=0;case '<=':return sbCmp(a,b)<=0}}
    case 'fn':{const A=n.a.map(x=>()=>sbEval(x,ctx));const a=i=>A[i]?A[i]():undefined;
      switch(n.n){
        case 'AND':return A.every(f=>!!sbTruth(f()));case 'OR':return A.some(f=>!!sbTruth(f()));case 'NOT':return !sbTruth(a(0));
        case 'IF':return sbTruth(a(0))?a(1):(A[2]?a(2):'');case 'BLANK':return '';
        case 'UPPER':return sbStr(a(0)).toUpperCase();case 'LOWER':return sbStr(a(0)).toLowerCase();case 'TRIM':return sbStr(a(0)).trim();
        case 'LEN':return sbStr(a(0)).length;
        case 'FIND':{const h=sbStr(a(1)),nd=sbStr(a(0));return h.indexOf(nd)+1}
        case 'SEARCH':{const h=sbStr(a(1)).toLowerCase(),nd=sbStr(a(0)).toLowerCase();return h.indexOf(nd)+1}
        case 'SUBSTITUTE':return sbStr(a(0)).split(sbStr(a(1))).join(sbStr(a(2)));
        case 'ARRAYJOIN':return sbStr(a(0));
        case 'VALUE':return +a(0)||0;
        case 'RECORD_ID':return String(ctx.row[sbPk(ctx.t)]);
        case 'CREATED_TIME':return ctx.row.created_at;
        case 'TODAY':case 'NOW':{const d=new Date();d.setHours(0,0,0,0);return d}
        case 'DATETIME_PARSE':return sbDate(a(0));
        case 'DATEADD':{const d=sbDate(a(0));if(!d)return null;const x=new Date(d);const k=+a(1)||0,u=String(a(2)||'days');if(/month/.test(u))x.setMonth(x.getMonth()+k);else if(/year/.test(u))x.setFullYear(x.getFullYear()+k);else if(/hour/.test(u))x.setHours(x.getHours()+k);else x.setDate(x.getDate()+k);return x}
        case 'IS_AFTER':{const x=sbDate(a(0)),y=sbDate(a(1));return !!(x&&y&&x>y)}
        case 'IS_BEFORE':{const x=sbDate(a(0)),y=sbDate(a(1));return !!(x&&y&&x<y)}
        case 'IS_SAME':{const x=sbDate(a(0)),y=sbDate(a(1));return !!(x&&y&&x.toDateString()===y.toDateString())}
        default:throw new Error('Fonction de formule non gérée : '+n.n)}}
  }}
const sbTruth=v=>v instanceof Date?true:Array.isArray(v)?v.length>0:!!v&&v!=='0';
function sbEq(a,b){if(typeof a==='boolean'||typeof b==='boolean')return !!sbTruth(a)===!!sbTruth(b);if(a===''||b==='')return sbStr(a)===''&&sbStr(b)==='';if(typeof a==='number'||typeof b==='number')return +a===+b;return sbStr(a)===sbStr(b)}
function sbCmp(a,b){if(typeof a==='number'||typeof b==='number')return (+a||0)-(+b||0);const x=sbStr(a),y=sbStr(b);return x<y?-1:x>y?1:0}

/* ---------- lecture ---------- */
const SB_CACHE={};
async function sbSelectAll(t,mois){
  const key=t.read+'|'+(mois||'');const c=SB_CACHE[key];if(c&&Date.now()-c.at<15000&&!t.write)return c.rows;
  const rows=[];let from=0;const N=1000;
  for(;;){let qy=SB.from(t.read).select('*').range(from,from+N-1);if(mois)qy=qy.eq('mois',mois);
    const {data,error}=await qy;if(error)throw new Error(error.message);rows.push(...data);if(data.length<N)break;from+=N}
  SB_CACHE[key]={at:Date.now(),rows};return rows;
}
async function sbList(t,u,mois){
  const P=u.searchParams;const byId=P.get('returnFieldsByFieldId')==='true';
  let rows=mois==='__none__'?[]:await sbSelectAll(t,mois);
  const formula=P.get('filterByFormula');
  if(formula){const ast=sbParse(formula);rows=rows.filter(row=>sbTruth(sbEval(ast,{t,row})))}
  const sf=P.get('sort[0][field]');
  if(sf){const f=t.byName[sf]||t.byId[sf];const dir=P.get('sort[0][direction]')==='desc'?-1:1;if(f)rows=[...rows].sort((x,y)=>{const a=x[f.col],b=y[f.col];if(a==null&&b==null)return 0;if(a==null)return 1;if(b==null)return -1;return (typeof a==='number'||!isNaN(+a)&&!isNaN(+b)&&a!==''&&b!==''?(+a)-(+b):String(a).localeCompare(String(b)))*dir})}
  const max=+P.get('maxRecords')||0;if(max)rows=rows.slice(0,max);
  const size=Math.min(+P.get('pageSize')||100,100),off=+P.get('offset')||0;
  const page=rows.slice(off,off+size);const urls=await sbSignUrls(t,page);
  const out={records:page.map(r=>sbRecord(t,r,byId,urls))};if(off+size<rows.length)out.offset=String(off+size);
  return out;
}
async function sbGetOne(t,id,byId){
  const {data,error}=await SB.from(t.read).select('*').eq(sbPk(t),id).maybeSingle();
  if(error)throw new Error(error.message);if(!data){const e=new Error('Enregistrement introuvable');e.status=404;throw e}
  return sbRecord(t,data,byId,await sbSignUrls(t,[data]));
}

/* ---------- écriture ---------- */
function sbCols(t,fields){
  const o={};for(const [k,v] of Object.entries(fields||{})){const f=t.byId[k]||t.byName[k];if(!f||f.ro||f.type==='att')continue;o[f.col]=sbToDb(f,v)}return o}
async function sbAttWrite(t,id,fields){ // suppression / réordonnancement des pièces jointes
  const f=t.fields.find(x=>x.type==='att'&&(fields[x.id]!==undefined||fields[x.name]!==undefined));if(!f)return;
  const want=(fields[f.id]!==undefined?fields[f.id]:fields[f.name])||[];
  const {data}=await SB.from(t.write).select(f.col).eq(sbPk(t),id).maybeSingle();const cur=(data&&data[f.col])||[];
  const keep=want.map(w=>cur.find(c=>c.id===(w.id||w))).filter(Boolean);
  const gone=cur.filter(c=>!keep.includes(c));if(gone.length)await SB.storage.from(SB_BUCKET).remove(gone.map(x=>x.path));
  const {error}=await SB.from(t.write).update({[f.col]:keep}).eq(sbPk(t),id);if(error)throw new Error(error.message);
}
async function sbCreate(t,recs,byId){
  if(!t.write)throw new Error('Table en lecture seule : '+t.name);
  const out=[];
  for(const r of recs){let row=sbCols(t,r.fields);
    if(t.write==='validations'){ // la base crée déjà les 17 étapes : on récupère la ligne existante
      const {data:ex}=await SB.from('validations').select('id').eq('id_formulaire',row.id_formulaire).eq('num_etape',row.num_etape).maybeSingle();
      if(ex){out.push(await sbGetOne(t,ex.id,byId));continue}}
    const {data,error}=await SB.from(t.write).insert(row).select(sbPk(t)).single();if(error)throw new Error(error.message);
    out.push(await sbGetOne(t,data[sbPk(t)],byId))}
  return out;
}
async function sbUpdate(t,recs,byId){
  if(!t.write)throw new Error('Table en lecture seule : '+t.name);
  const out=[];
  for(const r of recs){const row=sbCols(t,r.fields);
    if(t.write==='validations'&&('statut'in row||'verifie_par'in row||'date_verification'in row)){ // étapes automatiques : statut calculé par la base
      const {data:ex}=await SB.from('validations').select('num_etape').eq('id',r.id).maybeSingle();
      if(ex&&SB_AUTO_STEPS.includes(ex.num_etape)){delete row.statut;delete row.verifie_par;delete row.date_verification}}
    if(Object.keys(row).length){const {error}=await SB.from(t.write).update(row).eq(sbPk(t),r.id);if(error)throw new Error(error.message)}
    await sbAttWrite(t,r.id,r.fields||{});
    out.push(await sbGetOne(t,r.id,byId))}
  return out;
}

/* ---------- point d'entrée : imite l'API REST Airtable ---------- */
async function sbFetch(url,opt={}){
  const json=(o,status=200)=>new Response(JSON.stringify(o),{status,headers:{'Content-Type':'application/json'}});
  try{
    const u=new URL(url);const path=u.pathname.replace(/^\/v0\//,'');const method=(opt.method||'GET').toUpperCase();
    if(path==='meta/bases'){const {data,error}=await SB.from('ext_mois_transactions').select('mois');if(error)throw new Error(error.message);
      return json({bases:(data||[]).map(x=>{const [y,m]=x.mois.split('-');return {id:'sbTX_'+x.mois,name:`Transactions | ${SB_MOIS[+m-1]} ${y}`}})})}
    if(path.startsWith('meta/'))return json({tables:[]});
    const [base,table,recId]=path.split('/');const R=sbResolve(base,table);
    if(!R){if(method==='GET')return json({records:[]});return json({error:{type:'TABLE_NOT_FOUND',message:'Table inconnue : '+decodeURIComponent(table||'')}},404)}
    const t=R.t;const body=opt.body?JSON.parse(opt.body):{};const byId=u.searchParams.get('returnFieldsByFieldId')==='true'||body.returnFieldsByFieldId===true;
    if(method==='GET'){if(recId)return json(await sbGetOne(t,recId,byId));return json(await sbList(t,u,R.mois))}
    if(method==='POST'){const recs=body.records||[{fields:body.fields}];const out=await sbCreate(t,recs,byId!==false);return json(body.records?{records:out}:out[0])}
    if(method==='PATCH'||method==='PUT'){const recs=body.records||[{id:recId,fields:body.fields}];const out=await sbUpdate(t,recs,true);return json(body.records?{records:out}:out[0])}
    if(method==='DELETE'){const ids=recId?[recId]:u.searchParams.getAll('records[]');
      const {error}=await SB.from(t.write).delete().in(sbPk(t),ids);if(error)throw new Error(error.message);return json({records:ids.map(id=>({id,deleted:true}))})}
    return json({error:{type:'METHOD',message:method}},405);
  }catch(e){return json({error:{type:'SUPABASE',message:e.message}},e.status||422)}
}
/* téléversement d'un document scanné → Supabase Storage + liste « Documents scannés » du formulaire */
async function sbUpload(recId,file,filename){
  const t=SB_MAP[DEFAULT_TABLE];const f=t.byId[F.scans];
  const safe=String(filename||file.name||'document').replace(/[^\w.\-]+/g,'_');
  const path=`${recId}/${Date.now()}_${safe}`;
  const up=await SB.storage.from(SB_BUCKET).upload(path,file,{contentType:file.type,upsert:false});if(up.error)throw new Error(up.error.message);
  const {data,error}=await SB.from('formulaires').select(f.col).eq('id',recId).single();if(error)throw new Error(error.message);
  const list=[...(data[f.col]||[]),{id:'att'+Math.random().toString(36).slice(2,12),path,filename:filename||file.name,type:file.type,size:file.size,ajoute_le:new Date().toISOString()}];
  const r2=await SB.from('formulaires').update({[f.col]:list}).eq('id',recId);if(r2.error)throw new Error(r2.error.message);
  return sbGetOne(t,recId,true);
}
