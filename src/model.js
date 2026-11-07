export const roles={admin:'Admin',spv:'SPV',pic:'PIC Wilayah',sl:'Sub Leader',crm:'CRM'};
export const kinds={sales:'Repeat Order Sales',reseller:'Repeat Order Reseller',cross:'Cross Sales',new:'New Customer'};
export const money=n=>new Intl.NumberFormat('id-ID',{style:'currency',currency:'IDR',maximumFractionDigits:0}).format(n||0);
export const number=n=>new Intl.NumberFormat('id-ID').format(n||0);
export const today=()=>new Date().toLocaleDateString('en-CA',{timeZone:'Asia/Jakarta'});
export function visibleIds(me,profiles){
 if(!me||me.status!=='active')return [];
 if(['admin','spv'].includes(me.role))return profiles.map(p=>p.id);
 const result=new Set([me.id]);
 if(['pic','sl'].includes(me.role)){
  let changed=true;
  while(changed){changed=false;for(const p of profiles)if(['active','inactive'].includes(p.status)&&p.region_id===me.region_id&&result.has(p.manager_id)&&!result.has(p.id)){result.add(p.id);changed=true;}}
 }
 return [...result];
}
export function totals(rows){return rows.reduce((a,r)=>({revenue:a.revenue+Number(r.revenue||0),closing:a.closing+Number(r.closing||0),units:a.units+Number(r.units||0)}),{revenue:0,closing:0,units:0});}
export function validateReport(r){if(!r.product_id||!r.report_date||!kinds[r.kind])throw Error('Pilih tanggal, produk, dan jenis penjualan.');for(const k of ['closing','units'])if(!Number.isSafeInteger(Number(r[k]))||Number(r[k])<0)throw Error('Closing dan unit harus bilangan bulat positif atau nol.');if(Number(r.closing)>Number(r.units))throw Error('Jumlah unit minimal sama dengan closing.');if(Number(r.closing)===0&&Number(r.units)>0)throw Error('Isi closing untuk unit yang dilaporkan.');if(r.kind==='cross'&&(!Number.isFinite(Number(r.manual_revenue))||Number(r.manual_revenue)<0))throw Error('Omzet cross sales tidak valid.');return true;}
export function calcRevenue(r,p){return r.kind==='cross'?Number(r.manual_revenue||0):Number(r.units||0)*Number(r.kind==='reseller'?p.reseller_price:p.sales_price);}
export function canManage(me,p){return ['admin','spv'].includes(me.role)&&p.id!==me.id;}
export function csv(rows){return rows.map(r=>r.map(v=>'"'+String(v??'').replace(/^[=+@-]/,"'$&").replaceAll('"','""')+'"').join(',')).join('\r\n');}
