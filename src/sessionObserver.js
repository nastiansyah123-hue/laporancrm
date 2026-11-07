// Supabase emits SIGNED_IN on tab refocus too. Only identity changes clear app data.
export function observeSession(auth,{onSession,onIdentityChange,onReady,onError,onRefresh},{timeoutMs=10000}={}){
 let active=true,version=0,userId=null;
 const apply=(session,event)=>{if(!active)return;const nextId=session?.user?.id||null;if(nextId!==userId){userId=nextId;onIdentityChange(nextId);}onSession(session);if(event==='TOKEN_REFRESHED')onRefresh?.();onReady();};
 const{data}=auth.onAuthStateChange((event,session)=>{version++;apply(session,event)});
 const initialVersion=version;
 const timer=setTimeout(()=>{if(active&&version===initialVersion){onError(new Error('Pemeriksaan sesi terlalu lama. Silakan masuk kembali atau coba muat ulang.'));onReady();}},timeoutMs);
 Promise.resolve().then(()=>auth.getSession()).then(result=>{if(!active||version!==initialVersion)return;if(result.error)throw result.error;apply(result.data.session,'BOOTSTRAP');}).catch(error=>{if(active&&version===initialVersion){onError(error);onReady();}}).finally(()=>clearTimeout(timer));
 return()=>{active=false;clearTimeout(timer);data.subscription.unsubscribe();};
}
