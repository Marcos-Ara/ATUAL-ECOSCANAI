-- EcoScan 3.4.2: perfil completo + registro automático das análises salvas.

alter table public.profiles
  add column if not exists email text,
  add column if not exists updated_at timestamptz not null default now();

create or replace function public.ecoscan_sync_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles(id, email, full_name, updated_at)
  values(
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', ''),
    now()
  )
  on conflict(id) do update set
    email = excluded.email,
    full_name = excluded.full_name,
    updated_at = now();
  return new;
end;
$$;

revoke all on function public.ecoscan_sync_profile() from public, anon, authenticated;

drop trigger if exists ecoscan_profile on auth.users;
create trigger ecoscan_profile
after insert or update of email, raw_user_meta_data on auth.users
for each row execute function public.ecoscan_sync_profile();

insert into public.profiles(id, email, full_name, updated_at)
select
  id,
  email,
  coalesce(raw_user_meta_data->>'full_name', raw_user_meta_data->>'name', ''),
  now()
from auth.users
on conflict(id) do update set
  email = excluded.email,
  full_name = excluded.full_name,
  updated_at = now();

create table if not exists public.fato_scan (
  user_id uuid not null references auth.users(id) on delete cascade,
  client_scan_id text not null,
  object_name text,
  material_name text not null default '',
  category_name text not null default '',
  bin_name text not null default '',
  destination text not null default '',
  confidence double precision not null default 0 check(confidence between 0 and 1),
  source text not null default 'camera',
  detector text,
  detected_at timestamptz not null,
  latitude double precision check(latitude is null or latitude between -90 and 90),
  longitude double precision check(longitude is null or longitude between -180 and 180),
  created_at timestamptz not null default now(),
  primary key (user_id, client_scan_id)
);

create index if not exists fato_scan_user_detected_at_idx
  on public.fato_scan(user_id, detected_at desc);

alter table public.fato_scan enable row level security;
grant select, insert, update on public.fato_scan to authenticated;

drop policy if exists fato_scan_own_read on public.fato_scan;
create policy fato_scan_own_read
on public.fato_scan
for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists fato_scan_own_insert on public.fato_scan;
create policy fato_scan_own_insert
on public.fato_scan
for insert
to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists fato_scan_own_update on public.fato_scan;
create policy fato_scan_own_update
on public.fato_scan
for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);
