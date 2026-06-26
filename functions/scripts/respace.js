// Ré-espace les posts NON-mosaïque tous les STEP jours, en ENTRELAÇANT les
// visuels ai_* uniformément parmi les rubriques. Mosaïque intacte.
// Dry-run par défaut ; --commit pour appliquer.
const admin=require("firebase-admin");admin.initializeApp({projectId:"kilimandjaro-dev"});
const COMMIT=process.argv.includes("--commit");
const TODAY="2026-06-26", START="2026-06-28", STEP=2;
const WIN=new Set();for(let d=22;d<=27;d++)WIN.add("2026-06-"+d);
const add=(iso,n)=>{const d=new Date(iso+"T00:00:00Z");d.setUTCDate(d.getUTCDate()+n);return d.toISOString().slice(0,10);};
const byDateId=(a,b)=>a.date<b.date?-1:a.date>b.date?1:(a.id<b.id?-1:1);
(async()=>{const db=admin.firestore();
const s=await db.collection("instagram_queue").where("posted","==",false).get();
const all=[];s.forEach(d=>{const x=d.data();if((x.date||"")<TODAY&&!x.mosaic)return;all.push({ref:d.ref,id:d.id,date:x.date,mosaic:!!x.mosaic});});
const nm=all.filter(r=>!r.mosaic);
const rub=nm.filter(r=>!/^ai_/.test(r.id)).sort(byDateId);
const ai=nm.filter(r=>/^ai_/.test(r.id)).sort(byDateId);
const total=rub.length+ai.length;const merged=[];let ri=0,ac=0;
for(let k=0;k<total;k++){const wantAi=Math.floor((k+1)*ai.length/total)-Math.floor(k*ai.length/total)===1;
  if(wantAi&&ac<ai.length)merged.push(ai[ac++]);else if(ri<rub.length)merged.push(rub[ri++]);else merged.push(ai[ac++]);}
let cur=START;const plan=[];
for(const r of merged){while(WIN.has(cur))cur=add(cur,1);plan.push({...r,newDate:cur});cur=add(cur,STEP);}
console.log("Mode:",COMMIT?"COMMIT":"DRY-RUN","| rubriques:",rub.length,"+ IA:",ai.length,"=",total,"| mosaïque intacte:",all.filter(r=>r.mosaic).length,"\n");
plan.forEach(p=>console.log(" ",p.newDate,(/^ai_/.test(p.id)?"  🖼 ":"     "),p.id));
console.log("\nFenêtre:",plan[0].newDate,"→",plan[plan.length-1].newDate);
if(COMMIT){let b=db.batch(),n=0;for(const p of plan){if(p.newDate!==p.date){b.update(p.ref,{date:p.newDate});n++;if(n%400===0){await b.commit();b=db.batch();}}}await b.commit();console.log("MAJ:",n,"posts re-datés ✅");}
})().catch(e=>{console.error("ERR",e.message);process.exit(1);});
