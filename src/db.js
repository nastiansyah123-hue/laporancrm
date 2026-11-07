import {createClient} from '@supabase/supabase-js';
import {readAllRows} from './remoteRows.js';
export const supabase=import.meta.env.VITE_SUPABASE_URL&&import.meta.env.VITE_SUPABASE_ANON_KEY?createClient(import.meta.env.VITE_SUPABASE_URL,import.meta.env.VITE_SUPABASE_ANON_KEY):null;
export async function loadData(signal){const names=['regions','profiles','products','reports','targets'];const all=await Promise.all(names.map(n=>readAllRows(supabase,'crm_'+n,500,signal)));return Object.fromEntries(names.map((n,i)=>[n,all[i]]));}
export async function put(table,row,existing=false){const query=existing?supabase.from('crm_'+table).update(row).eq('id',row.id):supabase.from('crm_'+table).insert(row);const {data,error}=await query.select().single();if(error)throw error;return data;}
export async function rpc(name,args){const {error}=await supabase.rpc(name,args);if(error)throw error;}
