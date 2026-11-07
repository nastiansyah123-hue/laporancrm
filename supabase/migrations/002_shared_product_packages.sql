-- Sudah memasang CRM versi pertama? Jalankan file ini SAJA, sekali.
-- Produk menjadi master bersama. Semua laporan/omzet historis dipertahankan.
begin;
alter table crm_products alter column region_id drop not null;
alter table crm_products alter column sales_price set default 0;
alter table crm_products alter column reseller_price set default 0;
alter table crm_products drop constraint crm_products_region_id_name_key;
drop trigger crm_product_region on crm_products;
drop function crm_keep_product_region();
alter table crm_products add column packages jsonb not null default '[]'::jsonb;
alter table crm_reports add column package_lines jsonb;
-- Harga lama menjadi paket 1 unit. Harga paket lain diatur Admin/SPV.
update crm_products set packages=jsonb_build_array(
 jsonb_build_object('id','legacy-sales','name','Paket 1 '||unit,'units',1,'price',sales_price,'kind','sales','active',true),
 jsonb_build_object('id','legacy-reseller','name','Reseller 1 '||unit,'units',1,'price',reseller_price,'kind','reseller','active',true));
-- Jangan gabung atau menghapus produk lama karena nama sama; harga/riwayat dapat berbeda.
with ranked as(select id,row_number() over(partition by lower(trim(name)) order by id) n from crm_products)
update crm_products p set name=left(trim(p.name),45)||' · lama '||p.id::text from ranked r where r.id=p.id and r.n>1;
create unique index crm_product_global_name on crm_products(lower(trim(name)));
drop policy crm_products_read on crm_products;
create policy crm_products_read on crm_products for select to authenticated using(crm_role() is not null);
create or replace function public.crm_validate_packages() returns trigger language plpgsql set search_path=public as $$
declare item jsonb; cleaned jsonb='[]'; seen text[]='{}'; pid text; qty numeric; price numeric;
begin
 if jsonb_typeof(new.packages) is distinct from 'array' then raise exception 'Paket harus berupa daftar.';end if;
 if jsonb_array_length(new.packages) not between 1 and 50 then raise exception 'Isi 1 sampai 50 paket produk.';end if;
 for item in select value from jsonb_array_elements(new.packages) loop
  pid=item->>'id';
  if jsonb_typeof(item) is distinct from 'object' or coalesce(length(pid),0) not between 1 and 80 or pid=any(seen) then raise exception 'ID paket tidak valid atau duplikat.';end if;
  if jsonb_typeof(item->'name') is distinct from 'string' or length(trim(item->>'name')) not between 1 and 100 then raise exception 'Isi nama paket.';end if;
  if jsonb_typeof(item->'units') is distinct from 'number' or jsonb_typeof(item->'price') is distinct from 'number' then raise exception 'Isi jumlah unit dan harga paket.';end if;
  qty=(item->>'units')::numeric;price=(item->>'price')::numeric;
  if qty<>trunc(qty) or qty not between 1 and 100000 or price not between 0 and 1000000000000 or price<>round(price,2) then raise exception 'Jumlah unit atau harga paket tidak valid.';end if;
  if coalesce(item->>'kind','') not in ('sales','reseller') or jsonb_typeof(item->'active') is distinct from 'boolean' then raise exception 'Jenis atau status paket tidak valid.';end if;
  cleaned=cleaned||jsonb_build_array(jsonb_build_object('id',pid,'name',trim(item->>'name'),'units',qty,'price',price,'kind',item->>'kind','active',(item->>'active')::boolean));
  seen=array_append(seen,pid);
 end loop;
 new.packages=cleaned;return new;
end$$;
create trigger crm_product_packages before insert or update on crm_products for each row execute function crm_validate_packages();
create or replace function public.crm_prepare_report() returns trigger language plpgsql security definer set search_path=public as $$
declare person crm_profiles; product crm_products; line jsonb; snapshot jsonb; prior jsonb; cleaned jsonb='[]'; seen text[]='{}'; pid text; orders numeric; total_closing bigint=0; total_units bigint=0; total_revenue numeric=0; category text;
begin
 select * into person from crm_profiles where id=new.owner_id and status='active';
 if not found or person.region_id is null then raise exception 'Akun belum aktif atau belum memiliki wilayah.';end if;
 if auth.uid() is distinct from new.owner_id then raise exception 'Hanya pemilik yang dapat mengisi laporan pribadi.';end if;
 if TG_OP='UPDATE' then
  if new.owner_id<>old.owner_id or new.region_id<>old.region_id or new.product_id<>old.product_id or new.kind<>old.kind or new.report_date<>old.report_date then raise exception 'Identitas laporan tidak dapat diubah.';end if;
  new.created_at=old.created_at;
  if old.package_lines is null then
   if new.package_lines is not null or new.closing<>old.closing or new.units<>old.units or new.revenue<>old.revenue or new.unit_price<>old.unit_price or new.manual_revenue<>old.manual_revenue then raise exception 'Laporan lama dipertahankan tanpa mengubah angka historis.';end if;
   new.updated_at=now();return new;
  end if;
 else new.region_id=person.region_id;end if;
 if jsonb_typeof(new.package_lines) is distinct from 'array' then raise exception 'Isi jumlah order per paket.';end if;
 if jsonb_array_length(new.package_lines) not between 1 and 100 then raise exception 'Daftar order paket tidak valid.';end if;
 select * into product from crm_products where id=new.product_id;
 if not found then raise exception 'Produk tidak ditemukan.';end if;
 category=case when new.kind='reseller' then 'reseller' else 'sales' end;
 for line in select value from jsonb_array_elements(new.package_lines) loop
  pid=line->>'id';
  if coalesce(length(pid),0) not between 1 and 80 or pid=any(seen) or jsonb_typeof(line->'orders') is distinct from 'number' then raise exception 'Paket duplikat atau order tidak valid.';end if;
  orders=(line->>'orders')::numeric;
  if orders<>trunc(orders) or orders not between 0 and 1000000 then raise exception 'Jumlah order harus bilangan bulat positif atau nol.';end if;
  snapshot=null;
  if TG_OP='UPDATE' then
   select value into snapshot from jsonb_array_elements(old.package_lines) where value->>'id'=pid;
  end if;
  if snapshot is null then
   if not product.active then raise exception 'Produk sudah nonaktif.';end if;
   select value into snapshot from jsonb_array_elements(product.packages) where value->>'id'=pid and value->>'kind'=category and (value->>'active')::boolean;
  end if;
  if snapshot is null then raise exception 'Paket tidak aktif atau tidak sesuai jenis penjualan.';end if;
  cleaned=cleaned||jsonb_build_array(jsonb_build_object('id',pid,'name',snapshot->>'name','units',(snapshot->>'units')::integer,'price',(snapshot->>'price')::numeric,'kind',snapshot->>'kind','orders',orders));
  total_closing=total_closing+orders;total_units=total_units+orders*(snapshot->>'units')::integer;total_revenue=total_revenue+orders*(snapshot->>'price')::numeric;
  seen=array_append(seen,pid);
 end loop;
 if TG_OP='UPDATE' then
  for prior in select value from jsonb_array_elements(old.package_lines) loop
   if not (prior->>'id')=any(seen) then raise exception 'Paket tersimpan tidak boleh dihilangkan. Isi order 0 jika tidak ada.';end if;
  end loop;
 end if;
 if total_closing>2147483647 or total_units>2147483647 or total_revenue>9999999999999999.99 then raise exception 'Total laporan melebihi batas.';end if;
 new.package_lines=cleaned;new.closing=total_closing;new.units=total_units;new.revenue=total_revenue;new.unit_price=0;new.manual_revenue=0;new.updated_at=now();return new;
end$$;
revoke all on function crm_validate_packages() from public;
commit;
