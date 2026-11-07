-- CRM Adsy Team. Jalankan sekali di SQL Editor, pada project Supabase yang sama.
-- Tidak mengubah tabel, policy, maupun trigger aplikasi Akuisisi.
begin;
create table public.crm_regions(id uuid primary key default gen_random_uuid(),name text not null unique);
insert into public.crm_regions(name) values ('Kulon Progo'),('Purworejo');
create table public.crm_profiles(
 id uuid primary key references auth.users(id) on delete cascade,
 name text not null check(length(trim(name)) between 1 and 100), email text,
 role text not null default 'crm' check(role in ('admin','spv','pic','sl','crm')),
 status text not null default 'pending' check(status in ('pending','active','inactive','rejected')),
 region_id uuid references public.crm_regions(id),
 manager_id uuid references public.crm_profiles(id),
 created_at timestamptz not null default now(), check(manager_id is distinct from id)
);
create index crm_profiles_manager on public.crm_profiles(manager_id);
create or replace function public.crm_role() returns text language sql stable security definer set search_path=public as $$select role from crm_profiles where id=auth.uid() and status='active'$$;
create or replace function public.crm_region() returns uuid language sql stable security definer set search_path=public as $$select region_id from crm_profiles where id=auth.uid() and status='active'$$;
create or replace function public.crm_can_see(p_owner uuid) returns boolean language sql stable security definer set search_path=public as $$
 select coalesce(crm_role() in ('admin','spv') or (crm_role() is not null and p_owner=auth.uid()) or
 (crm_role() in ('pic','sl') and exists(
  with recursive tree as (
   select id,region_id,array[id] path from crm_profiles where manager_id=auth.uid() and status in ('active','inactive') and region_id=crm_region()
   union all select p.id,p.region_id,t.path||p.id from crm_profiles p join tree t on p.manager_id=t.id
    where p.status in ('active','inactive') and p.region_id=crm_region() and not p.id=any(t.path)
  ) select 1 from tree where id=p_owner
 )),false)
$$;
create table public.crm_products(
 id uuid primary key default gen_random_uuid(),region_id uuid not null references crm_regions(id),
 name text not null check(length(trim(name)) between 1 and 100),unit text not null default 'botol',
 sales_price numeric(16,2) not null check(sales_price>=0),reseller_price numeric(16,2) not null check(reseller_price>=0),active boolean not null default true,
 unique(region_id,name)
);
create or replace function public.crm_keep_product_region() returns trigger language plpgsql as $$
begin if new.region_id<>old.region_id then raise exception 'Wilayah produk tidak dapat dipindahkan. Buat produk baru di wilayah tujuan.';end if;return new;end$$;
create trigger crm_product_region before update on crm_products for each row execute function crm_keep_product_region();
create table public.crm_reports(
 id uuid primary key default gen_random_uuid(),owner_id uuid not null references crm_profiles(id),region_id uuid not null references crm_regions(id),
 product_id uuid not null references crm_products(id),report_date date not null,
 kind text not null check(kind in ('sales','reseller','cross','new')),
 closing integer not null default 0 check(closing>=0),units integer not null default 0 check(units>=0),
 unit_price numeric(16,2) not null default 0,manual_revenue numeric(16,2) not null default 0 check(manual_revenue>=0),revenue numeric(18,2) not null default 0,
 notes text not null default '' check(length(notes)<=2000),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(owner_id,report_date,product_id,kind),check(units>=closing),check(closing>0 or units=0)
);
create index crm_reports_scope on crm_reports(region_id,report_date,owner_id);
create table public.crm_targets(
 id uuid primary key default gen_random_uuid(),owner_id uuid not null references crm_profiles(id),region_id uuid not null references crm_regions(id),
 month date not null check(extract(day from month)=1),amount numeric(18,2) not null check(amount>=0),
 customer_total integer not null default 0 check(customer_total>=0),customer_active integer not null default 0 check(customer_active>=0 and customer_active<=customer_total),
 unique(owner_id,month)
);
create or replace function public.crm_prepare_report() returns trigger language plpgsql security definer set search_path=public as $$
declare person crm_profiles; product crm_products;
begin
 select * into person from crm_profiles where id=new.owner_id and status='active';
 if not found or person.region_id is null then raise exception 'Akun belum aktif atau belum memiliki wilayah.'; end if;
 if auth.uid() is distinct from new.owner_id then raise exception 'Hanya pemilik yang dapat mengisi laporan pribadi.';end if;
 if TG_OP='UPDATE' then
  if new.owner_id<>old.owner_id or new.region_id<>old.region_id or new.product_id<>old.product_id or new.kind<>old.kind or new.report_date<>old.report_date then raise exception 'Identitas laporan tidak dapat diubah.';end if;
  new.unit_price=old.unit_price;new.created_at=old.created_at;
 else
  new.region_id=person.region_id;
  select * into product from crm_products where id=new.product_id and active and region_id=person.region_id;
  if not found then raise exception 'Produk tidak aktif atau berbeda wilayah.';end if;
  new.unit_price=case when new.kind='reseller' then product.reseller_price else product.sales_price end;
 end if;
 new.revenue=case when new.kind='cross' then new.manual_revenue else new.units*new.unit_price end;
 new.updated_at=now();return new;
end$$;
create trigger crm_report_prepare before insert or update on crm_reports for each row execute function crm_prepare_report();
create or replace function public.crm_prepare_target() returns trigger language plpgsql security definer set search_path=public as $$
begin
 if crm_role() not in ('admin','spv') or crm_role() is null then raise exception 'Akses ditolak.';end if;
 select region_id into new.region_id from crm_profiles where id=new.owner_id and status='active';
 if new.region_id is null then raise exception 'Anggota belum memiliki wilayah.';end if;return new;
end$$;
create trigger crm_target_prepare before insert or update on crm_targets for each row execute function crm_prepare_target();
create or replace function public.crm_manage_profile(p_id uuid,p_name text,p_role text,p_status text,p_region uuid,p_manager uuid) returns void language plpgsql security definer set search_path=public as $$
declare m crm_profiles; oldp crm_profiles;
begin
 if crm_role() not in ('admin','spv') or crm_role() is null then raise exception 'Hanya Admin/SPV.';end if;
 if p_id=auth.uid() then raise exception 'Gunakan admin lain untuk mengubah akses akun sendiri.';end if;
 select * into oldp from crm_profiles where id=p_id for update;
 if not found then raise exception 'Akun tidak ditemukan.';end if;
 if p_role not in ('admin','spv','pic','sl','crm') or p_status not in ('active','inactive','rejected','pending') or length(trim(p_name)) not between 1 and 100 then raise exception 'Data akun tidak valid.';end if;
 if p_status='active' and p_role in ('pic','sl','crm') and p_region is null then raise exception 'Pilih wilayah anggota.';end if;
 if p_manager is not null then
  select * into m from crm_profiles where id=p_manager;
  if m.id is null or m.status<>'active' or m.region_id is distinct from p_region or p_id=p_manager or
    not ((p_role='sl' and m.role='pic') or (p_role='crm' and m.role in ('pic','sl'))) then raise exception 'Atasan harus aktif, sesuai hierarki dan wilayah.';end if;
 end if;
 if p_status='active' and p_role in ('sl','crm') and p_manager is null then raise exception 'Pilih atasan untuk anggota.';end if;
 if p_role in ('pic','admin','spv') and p_manager is not null then raise exception 'Peran ini tidak memerlukan atasan.';end if;
 if exists(select 1 from crm_profiles where manager_id=p_id and status='active') and (oldp.role<>p_role or oldp.region_id is distinct from p_region or p_status<>'active') then raise exception 'Pindahkan anggota bawahan dahulu sebelum mengubah akses atasan.';end if;
 update crm_profiles set name=trim(p_name),role=p_role,status=p_status,region_id=case when p_role in ('admin','spv') then null else p_region end,manager_id=p_manager where id=p_id;
end$$;
create or replace function public.crm_register_profile() returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.raw_user_meta_data->>'app' is distinct from 'crm_adsy' then return new;end if;
 insert into crm_profiles(id,name,email,role,status) values(new.id,left(coalesce(nullif(trim(new.raw_user_meta_data->>'display_name'),''),'Anggota CRM'),100),new.email,'crm','pending');return new;
end$$;
create trigger crm_signup after insert on auth.users for each row execute function crm_register_profile();
-- Akun yang sudah punya Auth (mis. aplikasi lain) dapat mengajukan profil CRM sendiri.
create or replace function public.crm_request_access(p_name text) returns void language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is null or length(trim(p_name)) not between 1 and 100 then raise exception 'Masuk dahulu dan isi nama.';end if;
 insert into crm_profiles(id,name,email) select auth.uid(),trim(p_name),email from auth.users where id=auth.uid() on conflict(id) do nothing;
end$$;
alter table crm_regions enable row level security;
alter table crm_profiles enable row level security;
alter table crm_products enable row level security;
alter table crm_reports enable row level security;
alter table crm_targets enable row level security;
create policy crm_regions_read on crm_regions for select to authenticated using(crm_role() is not null);
create policy crm_profiles_read on crm_profiles for select to authenticated using(id=auth.uid() or crm_can_see(id));
create policy crm_products_read on crm_products for select to authenticated using(crm_role() in ('admin','spv') or region_id=crm_region());
create policy crm_products_admin on crm_products for all to authenticated using(crm_role() in ('admin','spv')) with check(crm_role() in ('admin','spv'));
create policy crm_reports_read on crm_reports for select to authenticated using(crm_can_see(owner_id) and (owner_id=auth.uid() or crm_role() in ('admin','spv') or region_id=crm_region()));
create policy crm_reports_insert on crm_reports for insert to authenticated with check(owner_id=auth.uid() and crm_role() in ('pic','sl','crm') and region_id=crm_region());
create policy crm_reports_update on crm_reports for update to authenticated using(owner_id=auth.uid() and crm_role() in ('pic','sl','crm')) with check(owner_id=auth.uid() and crm_role() in ('pic','sl','crm'));
create policy crm_targets_read on crm_targets for select to authenticated using(crm_can_see(owner_id) and (owner_id=auth.uid() or crm_role() in ('admin','spv') or region_id=crm_region()));
create policy crm_targets_admin on crm_targets for all to authenticated using(crm_role() in ('admin','spv')) with check(crm_role() in ('admin','spv'));
grant select on crm_regions,crm_profiles to authenticated;
grant select,insert,update on crm_products,crm_reports,crm_targets to authenticated;
-- Hak akses profil hanya melalui RPC yang memeriksa admin, tanpa direct update.
revoke insert,update,delete on crm_profiles from anon,authenticated;
revoke delete on crm_regions,crm_products,crm_reports,crm_targets from anon,authenticated;
revoke all on crm_regions,crm_profiles,crm_products,crm_reports,crm_targets from anon;
revoke all on function crm_manage_profile(uuid,text,text,text,uuid,uuid),crm_request_access(text),crm_can_see(uuid),crm_role(),crm_region() from public;
grant execute on function crm_manage_profile(uuid,text,text,text,uuid,uuid),crm_request_access(text),crm_can_see(uuid),crm_role(),crm_region() to authenticated;
revoke all on function crm_register_profile(),crm_prepare_report(),crm_prepare_target(),crm_keep_product_region() from public;
commit;
