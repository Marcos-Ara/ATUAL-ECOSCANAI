-- EcoScan 3.3.0: estrutura para o projeto NOVO. Não apaga dados/schemas.
create schema if not exists extensions;
create extension if not exists unaccent with schema extensions;
create extension if not exists postgis with schema extensions;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
grant select, update on public.profiles to authenticated;
drop policy if exists profiles_own_read on public.profiles;
create policy profiles_own_read on public.profiles for select to authenticated using ((select auth.uid()) = id);
drop policy if exists profiles_own_update on public.profiles;
create policy profiles_own_update on public.profiles for update to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);
create or replace function public.ecoscan_sync_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id, full_name)
  values(new.id, coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', ''))
  on conflict(id) do update set full_name = excluded.full_name;
  return new;
end;
$$;
revoke all on function public.ecoscan_sync_profile() from public, anon, authenticated;
drop trigger if exists ecoscan_profile on auth.users;
create trigger ecoscan_profile after insert or update of raw_user_meta_data on auth.users
for each row execute function public.ecoscan_sync_profile();
insert into public.profiles(id,full_name)
select id, coalesce(raw_user_meta_data->>'full_name',raw_user_meta_data->>'name','') from auth.users
on conflict(id) do nothing;

create table if not exists public.ecopoints (
  id text primary key,
  name text not null,
  type text not null default 'Ecoponto oficial da Prefeitura de São Paulo',
  category text not null default 'recycling' check(category in ('recycling','disposal')),
  latitude double precision not null check(latitude between -90 and 90),
  longitude double precision not null check(longitude between -180 and 180),
  location extensions.geography(Point,4326) generated always as
    (extensions.ST_SetSRID(extensions.ST_MakePoint(longitude,latitude),4326)::extensions.geography) stored,
  address text,
  opening_hours text,
  accepted_material_ids text[] not null default '{}',
  accepted_materials_description text,
  district text,
  administrative_area text,
  source text not null default 'geosampa',
  source_url text,
  is_active boolean not null default true,
  updated_at timestamptz not null default now()
);
create index if not exists ecopoints_location_gist on public.ecopoints using gist(location);
alter table public.ecopoints enable row level security;
grant select on public.ecopoints to anon, authenticated;
drop policy if exists ecopoints_public_read on public.ecopoints;
create policy ecopoints_public_read on public.ecopoints for select to anon, authenticated using (is_active);

create table if not exists public.objects (
  object_id bigint primary key,
  object_name text not null,
  detection_class text,
  is_active boolean not null default true,
  is_ambiguous boolean not null default false,
  material_name text,
  category_name text,
  bin_name text,
  recommendation text,
  preparation_instructions text,
  special_waste jsonb not null default '[]',
  variant_count integer not null default 0
);
create table if not exists public.object_variants (
  variant_id bigint primary key,
  object_id bigint not null references public.objects(object_id) on delete cascade,
  material_name text,
  category_name text,
  bin_name text,
  recommendation text,
  preparation_instructions text
);
create table if not exists public.object_aliases (
  object_id bigint not null references public.objects(object_id) on delete cascade,
  variant_id bigint references public.object_variants(variant_id) on delete cascade,
  normalized_alias text not null,
  is_active boolean not null default true,
  unique nulls not distinct(object_id, variant_id, normalized_alias)
);
create index if not exists object_alias_search on public.object_aliases(normalized_alias);
alter table public.objects enable row level security;
alter table public.object_variants enable row level security;
alter table public.object_aliases enable row level security;
grant select on public.objects, public.object_variants, public.object_aliases to anon, authenticated;
drop policy if exists objects_public_read on public.objects;
create policy objects_public_read on public.objects for select to anon, authenticated using (is_active);
drop policy if exists variants_public_read on public.object_variants;
create policy variants_public_read on public.object_variants for select to anon, authenticated using (
  exists(select 1 from public.objects o where o.object_id = object_variants.object_id and o.is_active)
);
drop policy if exists aliases_public_read on public.object_aliases;
create policy aliases_public_read on public.object_aliases for select to anon, authenticated using (is_active);

create or replace function public.ecoscan_normalize_alias(p_alias text)
returns text language sql stable set search_path = '' as $$
select trim(regexp_replace(lower(extensions.unaccent(coalesce(p_alias,''))), '[^a-z0-9]+', ' ', 'g'));
$$;
create or replace function public.find_ecoscan_object(p_alias text)
returns jsonb language sql stable security invoker set search_path = '' as $$
select to_jsonb(o) || jsonb_build_object(
  'material_name',coalesce(v.material_name,o.material_name),
  'category_name',coalesce(v.category_name,o.category_name),
  'bin_name',coalesce(v.bin_name,o.bin_name),
  'recommendation',coalesce(v.recommendation,o.recommendation),
  'preparation_instructions',coalesce(v.preparation_instructions,o.preparation_instructions)
)
from public.objects o
left join public.object_aliases a on a.object_id = o.object_id and a.is_active
left join public.object_variants v on v.variant_id = a.variant_id
where o.is_active and (not o.is_ambiguous or (v.variant_id is not null and a.normalized_alias = public.ecoscan_normalize_alias(p_alias)))
and (
  a.normalized_alias = public.ecoscan_normalize_alias(p_alias)
  or public.ecoscan_normalize_alias(o.object_name) = public.ecoscan_normalize_alias(p_alias)
  or public.ecoscan_normalize_alias(o.detection_class) = public.ecoscan_normalize_alias(p_alias)
)
order by (a.normalized_alias = public.ecoscan_normalize_alias(p_alias)) desc nulls last,
  (v.variant_id is not null) desc, o.object_id
limit 1;
$$;
revoke all on function public.ecoscan_normalize_alias(text), public.find_ecoscan_object(text) from public;
grant execute on function public.ecoscan_normalize_alias(text), public.find_ecoscan_object(text) to anon, authenticated;
-- O histórico, a foto de perfil e as conquistas desta base ainda são locais.
-- Não se criam tabelas sem integração correspondente no aplicativo.
