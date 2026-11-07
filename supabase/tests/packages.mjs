import {PGlite}from'@electric-sql/pglite';import{readFile}from'node:fs/promises';import assert from'node:assert/strict';
const file=async p=>readFile(new URL(p,import.meta.url),'utf8');const id=n=>'00000000-0000-0000-0000-'+String(n).padStart(12,'0');
const packs=[{id:'one',name:'1 botol',units:1,price:10000,kind:'sales',active:true},{id:'two',name:'2 botol',units:2,price:15000,kind:'sales',active:true},{id:'res',name:'Reseller 6 botol',units:6,price:40000,kind:'reseller',active:true}];
for(const mode of ['fresh','upgrade']){
 const db=new PGlite();await db.exec(`create role authenticated;create role anon;create schema auth;create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb not null default '{}');create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;`);
 await db.exec(await file(mode==='fresh'?'../schema.sql':'./fixtures/001_legacy.sql'));
 const regions=(await db.query('select * from crm_regions order by name')).rows,[kp,pw]=regions.map(x=>x.id);
 for(let n=1;n<=8;n++)await db.query('insert into auth.users(id,email) values($1,$2)',[id(n),`a${n}@invalid.test`]);
 for(const [n,role,region,manager]of [[1,'admin',null,null],[2,'pic',kp,null],[3,'sl',kp,2],[4,'crm',kp,3],[5,'pic',pw,null],[6,'crm',pw,5],[7,'spv',null,null]])await db.query("insert into crm_profiles(id,name,role,status,region_id,manager_id) values($1,$2,$3,'active',$4,$5)",[id(n),'Person '+n,role,region,manager?id(manager):null]);
 const as=async n=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[n?id(n):'']);await db.exec('set role authenticated');};
 let legacy;
 if(mode==='upgrade'){
  await as(1);const old=(await db.query("insert into crm_products(region_id,name,unit,sales_price,reseller_price) values($1,'Herbapil','botol',120000,100000) returning *",[kp])).rows[0];await db.query("insert into crm_products(region_id,name,unit,sales_price,reseller_price) values($1,'Herbapil','botol',90000,80000)",[pw]);
  await as(4);legacy=(await db.query("insert into crm_reports(owner_id,region_id,product_id,report_date,kind,closing,units) values($1,$2,$3,'2026-10-01','sales',2,3) returning *",[id(4),kp,old.id])).rows[0];await db.exec('reset role');await db.exec(await file('../migrations/002_shared_product_packages.sql'));await as(1);
  const rows=(await db.query('select * from crm_products')).rows;assert.equal(rows.length,2,'migration retains both regional masters rather than losing price history');assert.equal(new Set(rows.map(x=>x.name)).size,2);const migrated=(await db.query('select * from crm_reports where id=$1',[legacy.id])).rows[0];assert.equal(Number(migrated.revenue),360000);assert.equal(migrated.package_lines,null);assert.equal(Number(rows.find(p=>p.id===old.id).packages[0].price),120000);
  await as(4);await assert.rejects(db.query('update crm_reports set package_lines=$1 where id=$2',[JSON.stringify([{id:'legacy-sales',orders:1}]),legacy.id]));await assert.rejects(db.query('update crm_reports set units=9 where id=$1',[legacy.id]));await assert.rejects(db.query('update crm_reports set revenue=1 where id=$1',[legacy.id]));
 }
 await as(1);const product=(await db.query("insert into crm_products(name,unit,packages) values('Produk Bersama','botol',$1) returning *",[JSON.stringify(packs)])).rows[0];
 await assert.rejects(db.query("insert into crm_products(name,unit,packages) values('produk bersama','botol',$1)",[JSON.stringify(packs)]),'global duplicate names blocked');
 for(const bad of [[],[packs[0],packs[0]],[{...packs[0],units:0}],[{...packs[0],units:1.5}],[{...packs[0],price:-1}],[{...packs[0],price:1.234}],[{...packs[0],kind:'bad'}]])await assert.rejects(db.query("insert into crm_products(name,unit,packages) values('Invalid','botol',$1)",[JSON.stringify(bad)]));
 const insert=async(n,date,kind,lines)=>db.query("insert into crm_reports(owner_id,region_id,product_id,report_date,kind,package_lines,closing,units,revenue,unit_price,manual_revenue) values($1,$2,$3,$4,$5,$6,999,999,1,1,1) returning *",[id(n),kp,product.id,date,kind,JSON.stringify(lines)]);
 await as(4);const report=(await insert(4,'2026-11-01','sales',[{id:'one',orders:3,price:1,units:99,name:'spoof'},{id:'two',orders:2,price:1}])).rows[0];assert.equal(report.closing,5);assert.equal(report.units,7);assert.equal(Number(report.revenue),60000);assert.equal(report.package_lines[0].name,'1 botol');assert.equal(Number(report.unit_price),0);assert.equal(Number(report.manual_revenue),0);
 await assert.rejects(insert(4,'2026-11-01','sales',[{id:'one',orders:1}]));
 for(const lines of [[{id:'one',orders:-1}],[{id:'one',orders:.5}],[{id:'one',orders:1},{id:'one',orders:1}],[{id:'unknown',orders:1}],[{id:'res',orders:1}],[]])await assert.rejects(insert(4,'2026-11-02','sales',lines));
 const reseller=(await insert(4,'2026-11-02','reseller',[{id:'res',orders:2}])).rows[0];assert.equal(reseller.closing,2);assert.equal(reseller.units,12);assert.equal(Number(reseller.revenue),80000);
 for(const kind of ['cross','new']){const r=(await insert(4,'2026-11-02',kind,[{id:'two',orders:2}])).rows[0];assert.equal(Number(r.revenue),30000);assert.equal(r.closing,2);}
 await as(6);assert.ok((await db.query('select * from crm_products where id=$1',[product.id])).rows.length,'same master visible in Purworejo');const pwReport=(await insert(6,'2026-11-01','sales',[{id:'one',orders:1}])).rows[0];assert.equal(pwReport.region_id,pw,'region comes from owner, not product or client');assert.equal((await db.query('select * from crm_reports')).rows.length,1,'CRM only own reports');
 await as(3);assert.ok((await db.query('select * from crm_reports where owner_id=$1',[id(4)])).rows.length>0);assert.equal((await db.query('select * from crm_reports where owner_id=$1',[id(6)])).rows.length,0);assert.equal((await db.query('select * from crm_reports where owner_id=$1',[id(2)])).rows.length,0);
 await as(2);assert.ok((await db.query('select * from crm_reports where owner_id=$1',[id(4)])).rows.length>0);
 await as(7);assert.ok((await db.query('select * from crm_reports where owner_id=$1',[id(6)])).rows.length>0,'SPV sees all regions');
 await as(1);const changed=[{...packs[0],price:99000,units:9,active:false},{...packs[1],price:25000},packs[2],{id:'three',name:'3 botol',units:3,price:20000,kind:'sales',active:true}];await db.query('update crm_products set packages=$1 where id=$2',[JSON.stringify(changed),product.id]);
 await as(4);const update=async lines=>db.query('update crm_reports set package_lines=$1,revenue=1,closing=1,units=1 where id=$2 returning *',[JSON.stringify(lines),report.id]);
 let updated=(await update([{id:'one',orders:4,price:1,units:9},{id:'two',orders:2},{id:'three',orders:1}])).rows[0];assert.equal(updated.closing,7);assert.equal(updated.units,11);assert.equal(Number(updated.revenue),90000,'stored packages keep old price/units, newly added package uses current master');
 await assert.rejects(update([{id:'two',orders:2},{id:'three',orders:1}]),'cannot drop historic package snapshot');
 await assert.rejects(insert(4,'2026-11-03','sales',[{id:'one',orders:1}]),'inactive package cannot be used in new report');
 const later=(await insert(4,'2026-11-03','sales',[{id:'two',orders:1}])).rows[0];assert.equal(Number(later.revenue),25000);
 await as(1);await db.query('update crm_products set active=false where id=$1',[product.id]);
 await as(4);updated=(await update([{id:'one',orders:1},{id:'two',orders:0},{id:'three',orders:0}])).rows[0];assert.equal(Number(updated.revenue),10000,'can edit stored snapshots after product deactivation');await assert.rejects(insert(4,'2026-11-04','sales',[{id:'two',orders:1}]));
 await as(8);await db.query("select crm_request_access('Pending')");assert.equal((await db.query('select * from crm_products')).rows.length,0,'pending has no catalog access');
 await db.close();console.log(`PASS ${mode}: shared catalog, legacy preservation, package validation, role/region RLS, authoritative totals, price snapshots, inactive packages/products, and all sales kinds.`);
}
