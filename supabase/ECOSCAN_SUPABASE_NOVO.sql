-- EcoScan AI: instalação inicial consolidada do banco Supabase, em português.
-- Execute este arquivo uma vez em um projeto sem tabelas do EcoScan.
-- Não execute também as migrações individuais desta pasta.
begin;

-- >>> MIGRATION 202609290000_core.sql
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
-- <<< MIGRATION 202609290000_core.sql

-- >>> MIGRATION 202609290001_ecoscan_ai.sql
-- EcoScan 3.2: model registry and opt-in training samples.
-- Apply with `supabase db push` using an administrator account.

create table if not exists public.ecoscan_model_releases (
  id bigint generated by default as identity primary key,
  platform text not null check (platform in ('android', 'ios')),
  version text not null,
  bucket_id text not null default 'ecoscan-models',
  object_path text not null,
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  byte_size bigint not null check (byte_size > 0),
  is_active boolean not null default false,
  notes text,
  created_at timestamptz not null default now(),
  unique (platform, version)
);

alter table public.ecoscan_model_releases enable row level security;
grant select on public.ecoscan_model_releases to authenticated;

drop policy if exists "authenticated users read active EcoScan models" on public.ecoscan_model_releases;
create policy "authenticated users read active EcoScan models"
on public.ecoscan_model_releases
for select
to authenticated
using (is_active = true);

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
) values (
  'ecoscan-models',
  'ecoscan-models',
  false,
  314572800,
  array['application/octet-stream', 'application/zip']
)
on conflict (id) do nothing;

drop policy if exists "authenticated users download released EcoScan models" on storage.objects;
create policy "authenticated users download released EcoScan models"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'ecoscan-models'
  and exists (
    select 1
    from public.ecoscan_model_releases release
    where release.bucket_id = storage.objects.bucket_id
      and release.object_path = storage.objects.name
      and release.is_active = true
  )
);

create table if not exists public.ecoscan_training_samples (
  user_id uuid not null references auth.users(id) on delete cascade,
  client_sample_id text not null,
  storage_path text not null,
  source text not null,
  detector text not null,
  detections jsonb not null default '[]'::jsonb,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected', 'trained')),
  verified_label text,
  verified_bin text,
  annotations jsonb not null default '[]'::jsonb,
  user_reported_label text,
  user_reported_bin text,
  report_note text,
  ai_detected boolean,
  original_label text,
  original_confidence double precision check (
    original_confidence is null or original_confidence between 0 and 1
  ),
  consented_at timestamptz not null default now(),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (user_id, client_sample_id)
);

alter table public.ecoscan_training_samples enable row level security;
grant select, insert, update on public.ecoscan_training_samples to authenticated;

drop policy if exists "users read their EcoScan training samples" on public.ecoscan_training_samples;
create policy "users read their EcoScan training samples"
on public.ecoscan_training_samples
for select
to authenticated
using (auth.uid() = user_id);

drop policy if exists "users create their EcoScan training samples" on public.ecoscan_training_samples;
create policy "users create their EcoScan training samples"
on public.ecoscan_training_samples
for insert
to authenticated
with check (
  auth.uid() = user_id
  and status = 'pending'
  and verified_label is null
  and annotations = '[]'::jsonb
);

drop policy if exists "users retry pending EcoScan training samples" on public.ecoscan_training_samples;
create policy "users retry pending EcoScan training samples"
on public.ecoscan_training_samples
for update
to authenticated
using (auth.uid() = user_id and status = 'pending')
with check (
  auth.uid() = user_id
  and status = 'pending'
  and verified_label is null
  and annotations = '[]'::jsonb
);

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
) values (
  'ecoscan-training',
  'ecoscan-training',
  false,
  10485760,
  array['image/jpeg']
)
on conflict (id) do nothing;

drop policy if exists "users upload their own EcoScan training images" on storage.objects;
create policy "users upload their own EcoScan training images"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'ecoscan-training'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "users replace their own pending training images" on storage.objects;
create policy "users replace their own pending training images"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'ecoscan-training'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'ecoscan-training'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "users read their own EcoScan training images" on storage.objects;
create policy "users read their own EcoScan training images"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'ecoscan-training'
  and (storage.foldername(name))[1] = auth.uid()::text
);
-- <<< MIGRATION 202609290001_ecoscan_ai.sql

-- >>> MIGRATION 202609290002_catalog.sql
-- Catálogo fornecido com a base: 133 objetos, 9 variantes e 216 aliases.
insert into public.objects select * from jsonb_populate_recordset(null::public.objects, '[{"object_id":1,"object_name":"Banana","detection_class":"banana","is_active":true,"is_ambiguous":false,"material_name":"Resíduos alimentares","category_name":"Resíduos Orgânicos","bin_name":"Marrom","recommendation":"Separe dos materiais recicláveis secos.","preparation_instructions":"Separe restos de alimentos dos materiais recicláveis secos.","special_waste":[],"variant_count":0},{"object_id":2,"object_name":"Maçã","detection_class":"apple","is_active":true,"is_ambiguous":false,"material_name":"Resíduos alimentares","category_name":"Resíduos Orgânicos","bin_name":"Marrom","recommendation":"Separe dos materiais recicláveis secos.","preparation_instructions":"Separe restos de alimentos dos materiais recicláveis secos.","special_waste":[],"variant_count":0},{"object_id":3,"object_name":"Laranja","detection_class":"orange","is_active":true,"is_ambiguous":false,"material_name":"Resíduos alimentares","category_name":"Resíduos Orgânicos","bin_name":"Marrom","recommendation":"Separe dos materiais recicláveis secos.","preparation_instructions":"Separe restos de alimentos dos materiais recicláveis secos.","special_waste":[],"variant_count":0},{"object_id":4,"object_name":"Brócolis","detection_class":"broccoli","is_active":true,"is_ambiguous":false,"material_name":"Resíduos alimentares","category_name":"Resíduos Orgânicos","bin_name":"Marrom","recommendation":"Separe dos materiais recicláveis secos.","preparation_instructions":"Separe restos de alimentos dos materiais recicláveis secos.","special_waste":[],"variant_count":0},{"object_id":5,"object_name":"Cenoura","detection_class":"carrot","is_active":true,"is_ambiguous":false,"material_name":"Resíduos alimentares","category_name":"Resíduos Orgânicos","bin_name":"Marrom","recommendation":"Separe dos materiais recicláveis secos.","preparation_instructions":"Separe restos de alimentos dos materiais recicláveis secos.","special_waste":[],"variant_count":0},{"object_id":6,"object_name":"Sanduíche","detection_class":"sandwich","is_active":true,"is_ambiguous":false,"material_name":"Resíduos alimentares","category_name":"Resíduos Orgânicos","bin_name":"Marrom","recommendation":"Separe dos materiais recicláveis secos.","preparation_instructions":"Separe restos de alimentos dos materiais recicláveis secos.","special_waste":[],"variant_count":0},{"object_id":7,"object_name":"Pizza","detection_class":"pizza","is_active":true,"is_ambiguous":false,"material_name":"Resíduos alimentares","category_name":"Resíduos Orgânicos","bin_name":"Marrom","recommendation":"Separe dos materiais recicláveis secos.","preparation_instructions":"Separe restos de alimentos dos materiais recicláveis secos.","special_waste":[],"variant_count":0},{"object_id":8,"object_name":"Rosquinha","detection_class":"donut","is_active":true,"is_ambiguous":false,"material_name":"Resíduos alimentares","category_name":"Resíduos Orgânicos","bin_name":"Marrom","recommendation":"Separe dos materiais recicláveis secos.","preparation_instructions":"Separe restos de alimentos dos materiais recicláveis secos.","special_waste":[],"variant_count":0},{"object_id":9,"object_name":"Bolo","detection_class":"cake","is_active":true,"is_ambiguous":false,"material_name":"Resíduos alimentares","category_name":"Resíduos Orgânicos","bin_name":"Marrom","recommendation":"Separe dos materiais recicláveis secos.","preparation_instructions":"Separe restos de alimentos dos materiais recicláveis secos.","special_waste":[],"variant_count":0},{"object_id":11,"object_name":"Garfo","detection_class":"fork","is_active":true,"is_ambiguous":true,"material_name":"Aço","category_name":"Metais","bin_name":"Amarela","recommendation":"Retire o excesso de resíduos e encaminhe para a coleta seletiva.","preparation_instructions":"Retire o excesso de conteúdo e mantenha o material separado.","special_waste":[],"variant_count":0},{"object_id":12,"object_name":"Faca","detection_class":"knife","is_active":true,"is_ambiguous":true,"material_name":"Aço","category_name":"Metais","bin_name":"Amarela","recommendation":"Retire o excesso de resíduos e encaminhe para a coleta seletiva.","preparation_instructions":"Retire o excesso de conteúdo e mantenha o material separado.","special_waste":[],"variant_count":0},{"object_id":13,"object_name":"Colher","detection_class":"spoon","is_active":true,"is_ambiguous":true,"material_name":"Aço","category_name":"Metais","bin_name":"Amarela","recommendation":"Retire o excesso de resíduos e encaminhe para a coleta seletiva.","preparation_instructions":"Retire o excesso de conteúdo e mantenha o material separado.","special_waste":[],"variant_count":0},{"object_id":14,"object_name":"Tesoura","detection_class":"scissors","is_active":true,"is_ambiguous":true,"material_name":"Aço","category_name":"Metais","bin_name":"Amarela","recommendation":"Retire o excesso de resíduos e encaminhe para a coleta seletiva.","preparation_instructions":"Retire o excesso de conteúdo e mantenha o material separado.","special_waste":[],"variant_count":0},{"object_id":16,"object_name":"Garrafa","detection_class":"bottle","is_active":true,"is_ambiguous":true,"material_name":null,"category_name":null,"bin_name":null,"recommendation":null,"preparation_instructions":null,"special_waste":[],"variant_count":3},{"object_id":17,"object_name":"Copo","detection_class":"cup","is_active":true,"is_ambiguous":true,"material_name":null,"category_name":null,"bin_name":null,"recommendation":null,"preparation_instructions":null,"special_waste":[],"variant_count":2},{"object_id":18,"object_name":"Tigela","detection_class":"bowl","is_active":true,"is_ambiguous":true,"material_name":null,"category_name":null,"bin_name":null,"recommendation":null,"preparation_instructions":null,"special_waste":[],"variant_count":2},{"object_id":19,"object_name":"Vaso","detection_class":"vase","is_active":true,"is_ambiguous":true,"material_name":null,"category_name":null,"bin_name":null,"recommendation":null,"preparation_instructions":null,"special_waste":[],"variant_count":2},{"object_id":20,"object_name":"Notebook","detection_class":"laptop","is_active":true,"is_ambiguous":false,"material_name":null,"category_name":null,"bin_name":null,"recommendation":null,"preparation_instructions":null,"special_waste":[],"variant_count":0},{"object_id":21,"object_name":"Mouse","detection_class":"mouse","is_active":true,"is_ambiguous":false,"material_name":null,"category_name":null,"bin_name":null,"recommendation":null,"preparation_instructions":null,"special_waste":[{"id":1,"name":"Eletrônicos","warning":"Não descarte equipamentos eletrônicos em lixeiras comuns.","risk_level":"medium","destination":"Logística reversa","instruction":"Procure pontos de coleta de eletroeletrônicos ou sistemas de logística reversa.","requires_special_handling":true,"requires_special_collection":true}],"variant_count":0},{"object_id":22,"object_name":"Teclado","detection_class":"keyboard","is_active":true,"is_ambiguous":false,"material_name":null,"category_name":null,"bin_name":null,"recommendation":null,"preparation_instructions":null,"special_waste":[{"id":1,"name":"Eletrônicos","warning":"Não descarte equipamentos eletrônicos em lixeiras comuns.","risk_level":"medium","destination":"Logística reversa","instruction":"Procure pontos de coleta de eletroeletrônicos ou sistemas de logística reversa.","requires_special_handling":true,"requires_special_collection":true}],"variant_count":0},{"object_id":23,"object_name":"Celular","detection_class":"cell_phone","is_active":true,"is_ambiguous":false,"material_name":null,"category_name":null,"bin_name":null,"recommendation":null,"preparation_instructions":null,"special_waste":[{"id":1,"name":"Eletrônicos","warning":"Não descarte equipamentos eletrônicos em lixeiras comuns.","risk_level":"medium","destination":"Logística reversa","instruction":"Procure pontos de coleta de eletroeletrônicos ou sistemas de logística reversa.","requires_special_handling":true,"requires_special_collection":true}],"variant_count":0},{"object_id":24,"object_name":"Televisão","detection_class":"tv","is_active":true,"is_ambiguous":false,"material_name":null,"category_name":null,"bin_name":null,"recommendation":null,"preparation_instructions":null,"special_waste":[{"id":1,"name":"Eletrônicos","warning":"Não descarte equipamentos eletrônicos em lixeiras comuns.","risk_level":"medium","destination":"Logística reversa","instruction":"Procure pontos de coleta de eletroeletrônicos ou sistemas de logística reversa.","requires_special_handling":true,"requires_special_collection":true}],"variant_count":0},{"object_id":25,"object_name":"Controle remoto","detection_class":"remote","is_active":true,"is_ambiguous":false,"material_name":null,"category_name":null,"bin_name":null,"recommendation":null,"preparation_instructions":null,"special_waste":[{"id":1,"name":"Eletrônicos","warning":"Não descarte equipamentos eletrônicos em lixeiras comuns.","risk_level":"medium","destination":"Logística reversa","instruction":"Procure pontos de coleta de eletroeletrônicos ou sistemas de logística reversa.","requires_special_handling":true,"requires_special_collection":true}],"variant_count":0},{"object_id":26,"object_name":"Micro-ondas","detection_class":"microwave","is_active":true,"is_ambiguous":false,"material_name":null,"category_name":null,"bin_name":null,"recommendation":null,"preparation_instructions":null,"special_waste":[],"variant_count":0},{"object_id":27,"object_name":"Forno","detection_class":"oven","is_active":true,"is_ambiguous":false,"material_name":null,"category_name":null,"bin_name":null,"recommendation":null,"preparation_instructions":null,"special_waste":[],"variant_count":0},{"object_id":28,"object_name":"Torradeira","detection_class":"toaster","is_active":true,"is_ambiguous":false,"material_name":null,"category_name":null,"bin_name":null,"recommendation":null,"preparation_instructions":null,"special_waste":[],"variant_count":0},{"object_id":29,"object_name":"Geladeira","detection_class":"refrigerator","is_active":true,"is_ambiguous":false,"material_name":null,"category_name":null,"bin_name":null,"recommendation":null,"preparation_instructions":null,"special_waste":[],"variant_count":0},{"object_id":30,"object_name":"Pessoa","detection_class":"person","is_active":true,"is_ambiguous":false,"material_name":null,"category_name":null,"bin_name":null,"recommendation":null,"preparation_instructions":null,"special_waste":[],"variant_count":0},{"object_id":31,"object_name":"Cachorro","detection_class":"dog","is_active":true,"is_ambiguous":false,"material_name":null,"category_name":null,"bin_name":null,"recommendation":null,"preparation_instructions":null,"special_waste":[],"variant_count":0},{"object_id":32,"object_name":"Gato","detection_class":"cat","is_active":true,"is_ambiguous":false,"material_name":null,"category_name":null,"bin_name":null,"recommendation":null,"preparation_instructions":null,"special_waste":[],"variant_count":0},{"object_id":33,"object_name":"Carro","detection_class":"car","is_active":true,"is_ambiguous":true,"material_name":null,"category_name":null,"bin_name":null,"recommendation":null,"preparation_instructions":null,"special_waste":[],"variant_count":0},{"object_id":34,"object_name":"Bicicleta","detection_class":"bicycle","is_active":true,"is_ambiguous":true,"material_name":null,"category_name":null,"bin_name":null,"recommendation":null,"preparation_instructions":null,"special_waste":[],"variant_count":0},{"object_id":35,"object_name":"Garrafa PET","detection_class":"bottle","is_active":true,"is_ambiguous":true,"material_name":"Plástico PET","category_name":"Plásticos","bin_name":"Vermelha","recommendation":"Esvazie a garrafa e descarte-a na coleta seletiva.","preparation_instructions":"Esvazie a embalagem e, quando possível, mantenha-a livre de restos de alimentos ou líquidos.","special_waste":[],"variant_count":0},{"object_id":10,"object_name":"Livro","detection_class":"book","is_active":true,"is_ambiguous":false,"material_name":"Papel","category_name":"Papel e Papelão","bin_name":"Azul","recommendation":"Mantenha o material seco e separado de resíduos orgânicos.","preparation_instructions":"Mantenha o papel seco, limpo e separado de resíduos orgânicos.","special_waste":[],"variant_count":0},{"object_id":15,"object_name":"Taça","detection_class":"wine_glass","is_active":true,"is_ambiguous":true,"material_name":"Vidro","category_name":"Vidros","bin_name":"Verde","recommendation":"Acondicione cuidadosamente o vidro quebrado para evitar acidentes.","preparation_instructions":"Esvazie o recipiente e acondicione vidro quebrado de forma segura para evitar acidentes.","special_waste":[],"variant_count":0},{"object_id":36,"object_name":"Sacola plástica","detection_class":null,"is_active":true,"is_ambiguous":false,"material_name":"Plástico comum","category_name":"Plásticos","bin_name":"Vermelha","recommendation":"Encaminhe o plástico para a coleta seletiva.","preparation_instructions":"Sempre que possível, esvazie e limpe o excesso de conteúdo antes da coleta.","special_waste":[],"variant_count":0},{"object_id":37,"object_name":"Embalagem plástica","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Plástico comum","category_name":"Plásticos","bin_name":"Vermelha","recommendation":"Encaminhe o plástico para a coleta seletiva.","preparation_instructions":"Sempre que possível, esvazie e limpe o excesso de conteúdo antes da coleta.","special_waste":[],"variant_count":0},{"object_id":38,"object_name":"Embalagem de shampoo","detection_class":"bottle","is_active":true,"is_ambiguous":true,"material_name":"PEAD (HDPE)","category_name":"Plásticos","bin_name":"Vermelha","recommendation":"Separe e mantenha o material limpo.","preparation_instructions":"Esvazie e mantenha a embalagem o mais limpa possível.","special_waste":[],"variant_count":0},{"object_id":39,"object_name":"Frasco de detergente","detection_class":"bottle","is_active":true,"is_ambiguous":true,"material_name":"PEAD (HDPE)","category_name":"Plásticos","bin_name":"Vermelha","recommendation":"Separe e mantenha o material limpo.","preparation_instructions":"Esvazie e mantenha a embalagem o mais limpa possível.","special_waste":[],"variant_count":0},{"object_id":40,"object_name":"Pote plástico","detection_class":"bowl","is_active":true,"is_ambiguous":true,"material_name":"Plástico comum","category_name":"Plásticos","bin_name":"Vermelha","recommendation":"Encaminhe o plástico para a coleta seletiva.","preparation_instructions":"Sempre que possível, esvazie e limpe o excesso de conteúdo antes da coleta.","special_waste":[],"variant_count":0},{"object_id":41,"object_name":"Pote de margarina","detection_class":"bowl","is_active":true,"is_ambiguous":true,"material_name":"Plástico comum","category_name":"Plásticos","bin_name":"Vermelha","recommendation":"Encaminhe o plástico para a coleta seletiva.","preparation_instructions":"Sempre que possível, esvazie e limpe o excesso de conteúdo antes da coleta.","special_waste":[],"variant_count":0},{"object_id":42,"object_name":"Pote de sorvete","detection_class":"bowl","is_active":true,"is_ambiguous":true,"material_name":"Plástico comum","category_name":"Plásticos","bin_name":"Vermelha","recommendation":"Encaminhe o plástico para a coleta seletiva.","preparation_instructions":"Sempre que possível, esvazie e limpe o excesso de conteúdo antes da coleta.","special_waste":[],"variant_count":0},{"object_id":43,"object_name":"Copo descartável plástico","detection_class":"cup","is_active":true,"is_ambiguous":true,"material_name":"Plástico comum","category_name":"Plásticos","bin_name":"Vermelha","recommendation":"Encaminhe o plástico para a coleta seletiva.","preparation_instructions":"Sempre que possível, esvazie e limpe o excesso de conteúdo antes da coleta.","special_waste":[],"variant_count":0},{"object_id":44,"object_name":"Tampa plástica","detection_class":null,"is_active":true,"is_ambiguous":false,"material_name":"Plástico comum","category_name":"Plásticos","bin_name":"Vermelha","recommendation":"Encaminhe o plástico para a coleta seletiva.","preparation_instructions":"Sempre que possível, esvazie e limpe o excesso de conteúdo antes da coleta.","special_waste":[],"variant_count":0},{"object_id":45,"object_name":"Canudo plástico","detection_class":null,"is_active":true,"is_ambiguous":false,"material_name":"Plástico comum","category_name":"Plásticos","bin_name":"Vermelha","recommendation":"Encaminhe o plástico para a coleta seletiva.","preparation_instructions":"Sempre que possível, esvazie e limpe o excesso de conteúdo antes da coleta.","special_waste":[],"variant_count":0},{"object_id":46,"object_name":"Talher plástico","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Plástico comum","category_name":"Plásticos","bin_name":"Vermelha","recommendation":"Encaminhe o plástico para a coleta seletiva.","preparation_instructions":"Sempre que possível, esvazie e limpe o excesso de conteúdo antes da coleta.","special_waste":[],"variant_count":0},{"object_id":47,"object_name":"Filme plástico","detection_class":null,"is_active":true,"is_ambiguous":false,"material_name":"Plástico comum","category_name":"Plásticos","bin_name":"Vermelha","recommendation":"Encaminhe o plástico para a coleta seletiva.","preparation_instructions":"Sempre que possível, esvazie e limpe o excesso de conteúdo antes da coleta.","special_waste":[],"variant_count":0},{"object_id":48,"object_name":"Galão plástico","detection_class":"bottle","is_active":true,"is_ambiguous":true,"material_name":"Plástico comum","category_name":"Plásticos","bin_name":"Vermelha","recommendation":"Encaminhe o plástico para a coleta seletiva.","preparation_instructions":"Sempre que possível, esvazie e limpe o excesso de conteúdo antes da coleta.","special_waste":[],"variant_count":0},{"object_id":49,"object_name":"Frasco plástico","detection_class":"bottle","is_active":true,"is_ambiguous":true,"material_name":"Plástico comum","category_name":"Plásticos","bin_name":"Vermelha","recommendation":"Encaminhe o plástico para a coleta seletiva.","preparation_instructions":"Sempre que possível, esvazie e limpe o excesso de conteúdo antes da coleta.","special_waste":[],"variant_count":0},{"object_id":50,"object_name":"Balde plástico","detection_class":null,"is_active":true,"is_ambiguous":false,"material_name":"Plástico comum","category_name":"Plásticos","bin_name":"Vermelha","recommendation":"Encaminhe o plástico para a coleta seletiva.","preparation_instructions":"Sempre que possível, esvazie e limpe o excesso de conteúdo antes da coleta.","special_waste":[],"variant_count":0},{"object_id":51,"object_name":"Bacia plástica","detection_class":"bowl","is_active":true,"is_ambiguous":false,"material_name":"Plástico comum","category_name":"Plásticos","bin_name":"Vermelha","recommendation":"Encaminhe o plástico para a coleta seletiva.","preparation_instructions":"Sempre que possível, esvazie e limpe o excesso de conteúdo antes da coleta.","special_waste":[],"variant_count":0},{"object_id":52,"object_name":"Escova de dentes","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Plástico comum","category_name":"Plásticos","bin_name":"Vermelha","recommendation":"Encaminhe o plástico para a coleta seletiva.","preparation_instructions":"Sempre que possível, esvazie e limpe o excesso de conteúdo antes da coleta.","special_waste":[],"variant_count":0},{"object_id":53,"object_name":"Pente plástico","detection_class":null,"is_active":true,"is_ambiguous":false,"material_name":"Plástico comum","category_name":"Plásticos","bin_name":"Vermelha","recommendation":"Encaminhe o plástico para a coleta seletiva.","preparation_instructions":"Sempre que possível, esvazie e limpe o excesso de conteúdo antes da coleta.","special_waste":[],"variant_count":0},{"object_id":54,"object_name":"Brinquedo plástico","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Plástico comum","category_name":"Plásticos","bin_name":"Vermelha","recommendation":"Encaminhe o plástico para a coleta seletiva.","preparation_instructions":"Sempre que possível, esvazie e limpe o excesso de conteúdo antes da coleta.","special_waste":[],"variant_count":0},{"object_id":55,"object_name":"Mangueira plástica","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Plástico comum","category_name":"Plásticos","bin_name":"Vermelha","recommendation":"Encaminhe o plástico para a coleta seletiva.","preparation_instructions":"Sempre que possível, esvazie e limpe o excesso de conteúdo antes da coleta.","special_waste":[],"variant_count":0},{"object_id":56,"object_name":"Tubulação plástica","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Plástico comum","category_name":"Plásticos","bin_name":"Vermelha","recommendation":"Encaminhe o plástico para a coleta seletiva.","preparation_instructions":"Sempre que possível, esvazie e limpe o excesso de conteúdo antes da coleta.","special_waste":[],"variant_count":0},{"object_id":57,"object_name":"Caixa organizadora plástica","detection_class":null,"is_active":true,"is_ambiguous":false,"material_name":"Plástico comum","category_name":"Plásticos","bin_name":"Vermelha","recommendation":"Encaminhe o plástico para a coleta seletiva.","preparation_instructions":"Sempre que possível, esvazie e limpe o excesso de conteúdo antes da coleta.","special_waste":[],"variant_count":0},{"object_id":58,"object_name":"Pote de cozinha plástico","detection_class":"bowl","is_active":true,"is_ambiguous":true,"material_name":"Plástico comum","category_name":"Plásticos","bin_name":"Vermelha","recommendation":"Encaminhe o plástico para a coleta seletiva.","preparation_instructions":"Sempre que possível, esvazie e limpe o excesso de conteúdo antes da coleta.","special_waste":[],"variant_count":0},{"object_id":59,"object_name":"Embalagem de alimento","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Plástico comum","category_name":"Plásticos","bin_name":"Vermelha","recommendation":"Encaminhe o plástico para a coleta seletiva.","preparation_instructions":"Sempre que possível, esvazie e limpe o excesso de conteúdo antes da coleta.","special_waste":[],"variant_count":0},{"object_id":60,"object_name":"Embalagem de biscoito","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Plástico comum","category_name":"Plásticos","bin_name":"Vermelha","recommendation":"Encaminhe o plástico para a coleta seletiva.","preparation_instructions":"Sempre que possível, esvazie e limpe o excesso de conteúdo antes da coleta.","special_waste":[],"variant_count":0},{"object_id":61,"object_name":"Embalagem de salgadinho","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Plástico comum","category_name":"Plásticos","bin_name":"Vermelha","recommendation":"Encaminhe o plástico para a coleta seletiva.","preparation_instructions":"Sempre que possível, esvazie e limpe o excesso de conteúdo antes da coleta.","special_waste":[],"variant_count":0},{"object_id":62,"object_name":"Embalagem de arroz","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Plástico comum","category_name":"Plásticos","bin_name":"Vermelha","recommendation":"Encaminhe o plástico para a coleta seletiva.","preparation_instructions":"Sempre que possível, esvazie e limpe o excesso de conteúdo antes da coleta.","special_waste":[],"variant_count":0},{"object_id":63,"object_name":"Embalagem de feijão","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Plástico comum","category_name":"Plásticos","bin_name":"Vermelha","recommendation":"Encaminhe o plástico para a coleta seletiva.","preparation_instructions":"Sempre que possível, esvazie e limpe o excesso de conteúdo antes da coleta.","special_waste":[],"variant_count":0},{"object_id":64,"object_name":"Saco plástico","detection_class":null,"is_active":true,"is_ambiguous":false,"material_name":"Plástico comum","category_name":"Plásticos","bin_name":"Vermelha","recommendation":"Encaminhe o plástico para a coleta seletiva.","preparation_instructions":"Sempre que possível, esvazie e limpe o excesso de conteúdo antes da coleta.","special_waste":[],"variant_count":0},{"object_id":65,"object_name":"Lacre plástico","detection_class":null,"is_active":true,"is_ambiguous":false,"material_name":"Plástico comum","category_name":"Plásticos","bin_name":"Vermelha","recommendation":"Encaminhe o plástico para a coleta seletiva.","preparation_instructions":"Sempre que possível, esvazie e limpe o excesso de conteúdo antes da coleta.","special_waste":[],"variant_count":0},{"object_id":66,"object_name":"Pote de cosmético","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Plástico comum","category_name":"Plásticos","bin_name":"Vermelha","recommendation":"Encaminhe o plástico para a coleta seletiva.","preparation_instructions":"Sempre que possível, esvazie e limpe o excesso de conteúdo antes da coleta.","special_waste":[],"variant_count":0},{"object_id":67,"object_name":"Frasco de cosmético","detection_class":"bottle","is_active":true,"is_ambiguous":true,"material_name":"Plástico comum","category_name":"Plásticos","bin_name":"Vermelha","recommendation":"Encaminhe o plástico para a coleta seletiva.","preparation_instructions":"Sempre que possível, esvazie e limpe o excesso de conteúdo antes da coleta.","special_waste":[],"variant_count":0},{"object_id":68,"object_name":"Embalagem de creme","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Plástico comum","category_name":"Plásticos","bin_name":"Vermelha","recommendation":"Encaminhe o plástico para a coleta seletiva.","preparation_instructions":"Sempre que possível, esvazie e limpe o excesso de conteúdo antes da coleta.","special_waste":[],"variant_count":0},{"object_id":69,"object_name":"Seringa plástica","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Plástico comum","category_name":"Plásticos","bin_name":"Vermelha","recommendation":"Encaminhe o plástico para a coleta seletiva.","preparation_instructions":"Sempre que possível, esvazie e limpe o excesso de conteúdo antes da coleta.","special_waste":[],"variant_count":0},{"object_id":70,"object_name":"Folha de papel","detection_class":null,"is_active":true,"is_ambiguous":false,"material_name":"Papel","category_name":"Papel e Papelão","bin_name":"Azul","recommendation":"Mantenha o material seco e separado de resíduos orgânicos.","preparation_instructions":"Mantenha o papel seco, limpo e separado de resíduos orgânicos.","special_waste":[],"variant_count":0},{"object_id":71,"object_name":"Jornal","detection_class":null,"is_active":true,"is_ambiguous":false,"material_name":"Papel","category_name":"Papel e Papelão","bin_name":"Azul","recommendation":"Mantenha o material seco e separado de resíduos orgânicos.","preparation_instructions":"Mantenha o papel seco, limpo e separado de resíduos orgânicos.","special_waste":[],"variant_count":0},{"object_id":72,"object_name":"Revista","detection_class":null,"is_active":true,"is_ambiguous":false,"material_name":"Papel","category_name":"Papel e Papelão","bin_name":"Azul","recommendation":"Mantenha o material seco e separado de resíduos orgânicos.","preparation_instructions":"Mantenha o papel seco, limpo e separado de resíduos orgânicos.","special_waste":[],"variant_count":0},{"object_id":73,"object_name":"Caderno","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Papel","category_name":"Papel e Papelão","bin_name":"Azul","recommendation":"Mantenha o material seco e separado de resíduos orgânicos.","preparation_instructions":"Mantenha o papel seco, limpo e separado de resíduos orgânicos.","special_waste":[],"variant_count":0},{"object_id":75,"object_name":"Cartolina","detection_class":null,"is_active":true,"is_ambiguous":false,"material_name":"Papel","category_name":"Papel e Papelão","bin_name":"Azul","recommendation":"Mantenha o material seco e separado de resíduos orgânicos.","preparation_instructions":"Mantenha o papel seco, limpo e separado de resíduos orgânicos.","special_waste":[],"variant_count":0},{"object_id":76,"object_name":"Papelão","detection_class":null,"is_active":true,"is_ambiguous":false,"material_name":"Papelão","category_name":"Papel e Papelão","bin_name":"Azul","recommendation":"Desmonte ou dobre as caixas antes do descarte.","preparation_instructions":"Achate ou desmonte as caixas quando possível e mantenha o papelão seco.","special_waste":[],"variant_count":0},{"object_id":77,"object_name":"Caixa de papelão","detection_class":null,"is_active":true,"is_ambiguous":false,"material_name":"Papelão","category_name":"Papel e Papelão","bin_name":"Azul","recommendation":"Desmonte ou dobre as caixas antes do descarte.","preparation_instructions":"Achate ou desmonte as caixas quando possível e mantenha o papelão seco.","special_waste":[],"variant_count":0},{"object_id":78,"object_name":"Caixa de cereal","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Papelão","category_name":"Papel e Papelão","bin_name":"Azul","recommendation":"Desmonte ou dobre as caixas antes do descarte.","preparation_instructions":"Achate ou desmonte as caixas quando possível e mantenha o papelão seco.","special_waste":[],"variant_count":0},{"object_id":79,"object_name":"Caixa de sapato","detection_class":null,"is_active":true,"is_ambiguous":false,"material_name":"Papelão","category_name":"Papel e Papelão","bin_name":"Azul","recommendation":"Desmonte ou dobre as caixas antes do descarte.","preparation_instructions":"Achate ou desmonte as caixas quando possível e mantenha o papelão seco.","special_waste":[],"variant_count":0},{"object_id":80,"object_name":"Caixa de mudança","detection_class":null,"is_active":true,"is_ambiguous":false,"material_name":"Papelão","category_name":"Papel e Papelão","bin_name":"Azul","recommendation":"Desmonte ou dobre as caixas antes do descarte.","preparation_instructions":"Achate ou desmonte as caixas quando possível e mantenha o papelão seco.","special_waste":[],"variant_count":0},{"object_id":81,"object_name":"Envelope de papel","detection_class":null,"is_active":true,"is_ambiguous":false,"material_name":"Papel","category_name":"Papel e Papelão","bin_name":"Azul","recommendation":"Mantenha o material seco e separado de resíduos orgânicos.","preparation_instructions":"Mantenha o papel seco, limpo e separado de resíduos orgânicos.","special_waste":[],"variant_count":0},{"object_id":82,"object_name":"Saco de papel","detection_class":null,"is_active":true,"is_ambiguous":false,"material_name":"Papel","category_name":"Papel e Papelão","bin_name":"Azul","recommendation":"Mantenha o material seco e separado de resíduos orgânicos.","preparation_instructions":"Mantenha o papel seco, limpo e separado de resíduos orgânicos.","special_waste":[],"variant_count":0},{"object_id":83,"object_name":"Papel de presente","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Papel","category_name":"Papel e Papelão","bin_name":"Azul","recommendation":"Mantenha o material seco e separado de resíduos orgânicos.","preparation_instructions":"Mantenha o papel seco, limpo e separado de resíduos orgânicos.","special_waste":[],"variant_count":0},{"object_id":84,"object_name":"Papel de embrulho","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Papel","category_name":"Papel e Papelão","bin_name":"Azul","recommendation":"Mantenha o material seco e separado de resíduos orgânicos.","preparation_instructions":"Mantenha o papel seco, limpo e separado de resíduos orgânicos.","special_waste":[],"variant_count":0},{"object_id":85,"object_name":"Papel impresso","detection_class":null,"is_active":true,"is_ambiguous":false,"material_name":"Papel","category_name":"Papel e Papelão","bin_name":"Azul","recommendation":"Mantenha o material seco e separado de resíduos orgânicos.","preparation_instructions":"Mantenha o papel seco, limpo e separado de resíduos orgânicos.","special_waste":[],"variant_count":0},{"object_id":86,"object_name":"Panfleto","detection_class":null,"is_active":true,"is_ambiguous":false,"material_name":"Papel","category_name":"Papel e Papelão","bin_name":"Azul","recommendation":"Mantenha o material seco e separado de resíduos orgânicos.","preparation_instructions":"Mantenha o papel seco, limpo e separado de resíduos orgânicos.","special_waste":[],"variant_count":0},{"object_id":87,"object_name":"Folder","detection_class":null,"is_active":true,"is_ambiguous":false,"material_name":"Papel","category_name":"Papel e Papelão","bin_name":"Azul","recommendation":"Mantenha o material seco e separado de resíduos orgânicos.","preparation_instructions":"Mantenha o papel seco, limpo e separado de resíduos orgânicos.","special_waste":[],"variant_count":0},{"object_id":88,"object_name":"Cartão","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Papel","category_name":"Papel e Papelão","bin_name":"Azul","recommendation":"Mantenha o material seco e separado de resíduos orgânicos.","preparation_instructions":"Mantenha o papel seco, limpo e separado de resíduos orgânicos.","special_waste":[],"variant_count":0},{"object_id":89,"object_name":"Cartão de visita","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Papel","category_name":"Papel e Papelão","bin_name":"Azul","recommendation":"Mantenha o material seco e separado de resíduos orgânicos.","preparation_instructions":"Mantenha o papel seco, limpo e separado de resíduos orgânicos.","special_waste":[],"variant_count":0},{"object_id":90,"object_name":"Cartaz","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Papel","category_name":"Papel e Papelão","bin_name":"Azul","recommendation":"Mantenha o material seco e separado de resíduos orgânicos.","preparation_instructions":"Mantenha o papel seco, limpo e separado de resíduos orgânicos.","special_waste":[],"variant_count":0},{"object_id":91,"object_name":"Apostila","detection_class":null,"is_active":true,"is_ambiguous":false,"material_name":"Papel","category_name":"Papel e Papelão","bin_name":"Azul","recommendation":"Mantenha o material seco e separado de resíduos orgânicos.","preparation_instructions":"Mantenha o papel seco, limpo e separado de resíduos orgânicos.","special_waste":[],"variant_count":0},{"object_id":92,"object_name":"Bilhete de papel","detection_class":null,"is_active":true,"is_ambiguous":false,"material_name":"Papel","category_name":"Papel e Papelão","bin_name":"Azul","recommendation":"Mantenha o material seco e separado de resíduos orgânicos.","preparation_instructions":"Mantenha o papel seco, limpo e separado de resíduos orgânicos.","special_waste":[],"variant_count":0},{"object_id":93,"object_name":"Guardanapo de papel","detection_class":null,"is_active":true,"is_ambiguous":false,"material_name":"Papel","category_name":"Papel e Papelão","bin_name":"Azul","recommendation":"Mantenha o material seco e separado de resíduos orgânicos.","preparation_instructions":"Mantenha o papel seco, limpo e separado de resíduos orgânicos.","special_waste":[],"variant_count":0},{"object_id":94,"object_name":"Papel toalha","detection_class":null,"is_active":true,"is_ambiguous":false,"material_name":"Papel","category_name":"Papel e Papelão","bin_name":"Azul","recommendation":"Mantenha o material seco e separado de resíduos orgânicos.","preparation_instructions":"Mantenha o papel seco, limpo e separado de resíduos orgânicos.","special_waste":[],"variant_count":0},{"object_id":99,"object_name":"Tubo de papelão","detection_class":null,"is_active":true,"is_ambiguous":false,"material_name":"Papelão","category_name":"Papel e Papelão","bin_name":"Azul","recommendation":"Desmonte ou dobre as caixas antes do descarte.","preparation_instructions":"Achate ou desmonte as caixas quando possível e mantenha o papelão seco.","special_waste":[],"variant_count":0},{"object_id":95,"object_name":"Filtro de café de papel","detection_class":null,"is_active":true,"is_ambiguous":false,"material_name":"Papel","category_name":"Papel e Papelão","bin_name":"Azul","recommendation":"Mantenha o material seco e separado de resíduos orgânicos.","preparation_instructions":"Mantenha o papel seco, limpo e separado de resíduos orgânicos.","special_waste":[],"variant_count":0},{"object_id":96,"object_name":"Papel para impressora","detection_class":null,"is_active":true,"is_ambiguous":false,"material_name":"Papel","category_name":"Papel e Papelão","bin_name":"Azul","recommendation":"Mantenha o material seco e separado de resíduos orgânicos.","preparation_instructions":"Mantenha o papel seco, limpo e separado de resíduos orgânicos.","special_waste":[],"variant_count":0},{"object_id":97,"object_name":"Folha de caderno","detection_class":null,"is_active":true,"is_ambiguous":false,"material_name":"Papel","category_name":"Papel e Papelão","bin_name":"Azul","recommendation":"Mantenha o material seco e separado de resíduos orgânicos.","preparation_instructions":"Mantenha o papel seco, limpo e separado de resíduos orgânicos.","special_waste":[],"variant_count":0},{"object_id":98,"object_name":"Papelão ondulado","detection_class":null,"is_active":true,"is_ambiguous":false,"material_name":"Papelão","category_name":"Papel e Papelão","bin_name":"Azul","recommendation":"Desmonte ou dobre as caixas antes do descarte.","preparation_instructions":"Achate ou desmonte as caixas quando possível e mantenha o papelão seco.","special_waste":[],"variant_count":0},{"object_id":100,"object_name":"Rolo de papelão","detection_class":null,"is_active":true,"is_ambiguous":false,"material_name":"Papelão","category_name":"Papel e Papelão","bin_name":"Azul","recommendation":"Desmonte ou dobre as caixas antes do descarte.","preparation_instructions":"Achate ou desmonte as caixas quando possível e mantenha o papelão seco.","special_waste":[],"variant_count":0},{"object_id":101,"object_name":"Bandeja de papelão","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Papelão","category_name":"Papel e Papelão","bin_name":"Azul","recommendation":"Desmonte ou dobre as caixas antes do descarte.","preparation_instructions":"Achate ou desmonte as caixas quando possível e mantenha o papelão seco.","special_waste":[],"variant_count":0},{"object_id":102,"object_name":"Embalagem de papel","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Papel","category_name":"Papel e Papelão","bin_name":"Azul","recommendation":"Mantenha o material seco e separado de resíduos orgânicos.","preparation_instructions":"Mantenha o papel seco, limpo e separado de resíduos orgânicos.","special_waste":[],"variant_count":0},{"object_id":103,"object_name":"Embalagem de papelão","detection_class":null,"is_active":true,"is_ambiguous":false,"material_name":"Papelão","category_name":"Papel e Papelão","bin_name":"Azul","recommendation":"Desmonte ou dobre as caixas antes do descarte.","preparation_instructions":"Achate ou desmonte as caixas quando possível e mantenha o papelão seco.","special_waste":[],"variant_count":0},{"object_id":104,"object_name":"Garrafa de vidro","detection_class":"bottle","is_active":true,"is_ambiguous":true,"material_name":"Vidro","category_name":"Vidros","bin_name":"Verde","recommendation":"Acondicione cuidadosamente o vidro quebrado para evitar acidentes.","preparation_instructions":"Esvazie o recipiente e acondicione vidro quebrado de forma segura para evitar acidentes.","special_waste":[],"variant_count":0},{"object_id":105,"object_name":"Pote de vidro","detection_class":"bowl","is_active":true,"is_ambiguous":true,"material_name":"Vidro","category_name":"Vidros","bin_name":"Verde","recommendation":"Acondicione cuidadosamente o vidro quebrado para evitar acidentes.","preparation_instructions":"Esvazie o recipiente e acondicione vidro quebrado de forma segura para evitar acidentes.","special_waste":[],"variant_count":0},{"object_id":106,"object_name":"Pote de conserva de vidro","detection_class":"bottle","is_active":true,"is_ambiguous":true,"material_name":"Vidro","category_name":"Vidros","bin_name":"Verde","recommendation":"Acondicione cuidadosamente o vidro quebrado para evitar acidentes.","preparation_instructions":"Esvazie o recipiente e acondicione vidro quebrado de forma segura para evitar acidentes.","special_waste":[],"variant_count":0},{"object_id":107,"object_name":"Frasco de vidro","detection_class":"bottle","is_active":true,"is_ambiguous":true,"material_name":"Vidro","category_name":"Vidros","bin_name":"Verde","recommendation":"Acondicione cuidadosamente o vidro quebrado para evitar acidentes.","preparation_instructions":"Esvazie o recipiente e acondicione vidro quebrado de forma segura para evitar acidentes.","special_waste":[],"variant_count":0},{"object_id":108,"object_name":"Frasco de perfume de vidro","detection_class":"bottle","is_active":true,"is_ambiguous":true,"material_name":"Vidro","category_name":"Vidros","bin_name":"Verde","recommendation":"Acondicione cuidadosamente o vidro quebrado para evitar acidentes.","preparation_instructions":"Esvazie o recipiente e acondicione vidro quebrado de forma segura para evitar acidentes.","special_waste":[],"variant_count":0},{"object_id":109,"object_name":"Copo de vidro","detection_class":"cup","is_active":true,"is_ambiguous":true,"material_name":"Vidro","category_name":"Vidros","bin_name":"Verde","recommendation":"Acondicione cuidadosamente o vidro quebrado para evitar acidentes.","preparation_instructions":"Esvazie o recipiente e acondicione vidro quebrado de forma segura para evitar acidentes.","special_waste":[],"variant_count":0},{"object_id":110,"object_name":"Taça de vidro","detection_class":"wine_glass","is_active":true,"is_ambiguous":true,"material_name":"Vidro","category_name":"Vidros","bin_name":"Verde","recommendation":"Acondicione cuidadosamente o vidro quebrado para evitar acidentes.","preparation_instructions":"Esvazie o recipiente e acondicione vidro quebrado de forma segura para evitar acidentes.","special_waste":[],"variant_count":0},{"object_id":111,"object_name":"Jarra de vidro","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Vidro","category_name":"Vidros","bin_name":"Verde","recommendation":"Acondicione cuidadosamente o vidro quebrado para evitar acidentes.","preparation_instructions":"Esvazie o recipiente e acondicione vidro quebrado de forma segura para evitar acidentes.","special_waste":[],"variant_count":0},{"object_id":112,"object_name":"Travessa de vidro","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Vidro","category_name":"Vidros","bin_name":"Verde","recommendation":"Acondicione cuidadosamente o vidro quebrado para evitar acidentes.","preparation_instructions":"Esvazie o recipiente e acondicione vidro quebrado de forma segura para evitar acidentes.","special_waste":[],"variant_count":0},{"object_id":113,"object_name":"Assadeira de vidro","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Vidro","category_name":"Vidros","bin_name":"Verde","recommendation":"Acondicione cuidadosamente o vidro quebrado para evitar acidentes.","preparation_instructions":"Esvazie o recipiente e acondicione vidro quebrado de forma segura para evitar acidentes.","special_waste":[],"variant_count":0},{"object_id":114,"object_name":"Pote hermético de vidro","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Vidro","category_name":"Vidros","bin_name":"Verde","recommendation":"Acondicione cuidadosamente o vidro quebrado para evitar acidentes.","preparation_instructions":"Esvazie o recipiente e acondicione vidro quebrado de forma segura para evitar acidentes.","special_waste":[],"variant_count":0},{"object_id":115,"object_name":"Recipiente de vidro","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Vidro","category_name":"Vidros","bin_name":"Verde","recommendation":"Acondicione cuidadosamente o vidro quebrado para evitar acidentes.","preparation_instructions":"Esvazie o recipiente e acondicione vidro quebrado de forma segura para evitar acidentes.","special_waste":[],"variant_count":0},{"object_id":116,"object_name":"Vidro de conserva","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Vidro","category_name":"Vidros","bin_name":"Verde","recommendation":"Acondicione cuidadosamente o vidro quebrado para evitar acidentes.","preparation_instructions":"Esvazie o recipiente e acondicione vidro quebrado de forma segura para evitar acidentes.","special_waste":[],"variant_count":0},{"object_id":117,"object_name":"Garrafa de vinho de vidro","detection_class":"bottle","is_active":true,"is_ambiguous":true,"material_name":"Vidro","category_name":"Vidros","bin_name":"Verde","recommendation":"Acondicione cuidadosamente o vidro quebrado para evitar acidentes.","preparation_instructions":"Esvazie o recipiente e acondicione vidro quebrado de forma segura para evitar acidentes.","special_waste":[],"variant_count":0},{"object_id":118,"object_name":"Garrafa de cerveja de vidro","detection_class":"bottle","is_active":true,"is_ambiguous":true,"material_name":"Vidro","category_name":"Vidros","bin_name":"Verde","recommendation":"Acondicione cuidadosamente o vidro quebrado para evitar acidentes.","preparation_instructions":"Esvazie o recipiente e acondicione vidro quebrado de forma segura para evitar acidentes.","special_waste":[],"variant_count":0},{"object_id":119,"object_name":"Garrafa de suco de vidro","detection_class":"bottle","is_active":true,"is_ambiguous":true,"material_name":"Vidro","category_name":"Vidros","bin_name":"Verde","recommendation":"Acondicione cuidadosamente o vidro quebrado para evitar acidentes.","preparation_instructions":"Esvazie o recipiente e acondicione vidro quebrado de forma segura para evitar acidentes.","special_waste":[],"variant_count":0},{"object_id":120,"object_name":"Garrafa de refrigerante de vidro","detection_class":"bottle","is_active":true,"is_ambiguous":true,"material_name":"Vidro","category_name":"Vidros","bin_name":"Verde","recommendation":"Acondicione cuidadosamente o vidro quebrado para evitar acidentes.","preparation_instructions":"Esvazie o recipiente e acondicione vidro quebrado de forma segura para evitar acidentes.","special_waste":[],"variant_count":0},{"object_id":121,"object_name":"Pote de molho de vidro","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Vidro","category_name":"Vidros","bin_name":"Verde","recommendation":"Acondicione cuidadosamente o vidro quebrado para evitar acidentes.","preparation_instructions":"Esvazie o recipiente e acondicione vidro quebrado de forma segura para evitar acidentes.","special_waste":[],"variant_count":0},{"object_id":122,"object_name":"Pote de geleia de vidro","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Vidro","category_name":"Vidros","bin_name":"Verde","recommendation":"Acondicione cuidadosamente o vidro quebrado para evitar acidentes.","preparation_instructions":"Esvazie o recipiente e acondicione vidro quebrado de forma segura para evitar acidentes.","special_waste":[],"variant_count":0},{"object_id":123,"object_name":"Pote de palmito de vidro","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Vidro","category_name":"Vidros","bin_name":"Verde","recommendation":"Acondicione cuidadosamente o vidro quebrado para evitar acidentes.","preparation_instructions":"Esvazie o recipiente e acondicione vidro quebrado de forma segura para evitar acidentes.","special_waste":[],"variant_count":0},{"object_id":124,"object_name":"Pote de azeitona de vidro","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Vidro","category_name":"Vidros","bin_name":"Verde","recommendation":"Acondicione cuidadosamente o vidro quebrado para evitar acidentes.","preparation_instructions":"Esvazie o recipiente e acondicione vidro quebrado de forma segura para evitar acidentes.","special_waste":[],"variant_count":0},{"object_id":125,"object_name":"Pote de café de vidro","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Vidro","category_name":"Vidros","bin_name":"Verde","recommendation":"Acondicione cuidadosamente o vidro quebrado para evitar acidentes.","preparation_instructions":"Esvazie o recipiente e acondicione vidro quebrado de forma segura para evitar acidentes.","special_waste":[],"variant_count":0},{"object_id":126,"object_name":"Pote de tempero de vidro","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Vidro","category_name":"Vidros","bin_name":"Verde","recommendation":"Acondicione cuidadosamente o vidro quebrado para evitar acidentes.","preparation_instructions":"Esvazie o recipiente e acondicione vidro quebrado de forma segura para evitar acidentes.","special_waste":[],"variant_count":0},{"object_id":127,"object_name":"Pote de cozinha de vidro","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Vidro","category_name":"Vidros","bin_name":"Verde","recommendation":"Acondicione cuidadosamente o vidro quebrado para evitar acidentes.","preparation_instructions":"Esvazie o recipiente e acondicione vidro quebrado de forma segura para evitar acidentes.","special_waste":[],"variant_count":0},{"object_id":128,"object_name":"Garrafa decorativa de vidro","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Vidro","category_name":"Vidros","bin_name":"Verde","recommendation":"Acondicione cuidadosamente o vidro quebrado para evitar acidentes.","preparation_instructions":"Esvazie o recipiente e acondicione vidro quebrado de forma segura para evitar acidentes.","special_waste":[],"variant_count":0},{"object_id":129,"object_name":"Vaso de vidro","detection_class":"vase","is_active":true,"is_ambiguous":true,"material_name":"Vidro","category_name":"Vidros","bin_name":"Verde","recommendation":"Acondicione cuidadosamente o vidro quebrado para evitar acidentes.","preparation_instructions":"Esvazie o recipiente e acondicione vidro quebrado de forma segura para evitar acidentes.","special_waste":[],"variant_count":0},{"object_id":130,"object_name":"Objeto decorativo de vidro","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Vidro","category_name":"Vidros","bin_name":"Verde","recommendation":"Acondicione cuidadosamente o vidro quebrado para evitar acidentes.","preparation_instructions":"Esvazie o recipiente e acondicione vidro quebrado de forma segura para evitar acidentes.","special_waste":[],"variant_count":0},{"object_id":131,"object_name":"Placa de vidro","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Vidro","category_name":"Vidros","bin_name":"Verde","recommendation":"Acondicione cuidadosamente o vidro quebrado para evitar acidentes.","preparation_instructions":"Esvazie o recipiente e acondicione vidro quebrado de forma segura para evitar acidentes.","special_waste":[],"variant_count":0},{"object_id":132,"object_name":"Tubo de vidro","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Vidro","category_name":"Vidros","bin_name":"Verde","recommendation":"Acondicione cuidadosamente o vidro quebrado para evitar acidentes.","preparation_instructions":"Esvazie o recipiente e acondicione vidro quebrado de forma segura para evitar acidentes.","special_waste":[],"variant_count":0},{"object_id":133,"object_name":"Vidro de embalagem","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Vidro","category_name":"Vidros","bin_name":"Verde","recommendation":"Acondicione cuidadosamente o vidro quebrado para evitar acidentes.","preparation_instructions":"Esvazie o recipiente e acondicione vidro quebrado de forma segura para evitar acidentes.","special_waste":[],"variant_count":0},{"object_id":134,"object_name":"Embalagem de vidro","detection_class":null,"is_active":true,"is_ambiguous":true,"material_name":"Vidro","category_name":"Vidros","bin_name":"Verde","recommendation":"Acondicione cuidadosamente o vidro quebrado para evitar acidentes.","preparation_instructions":"Esvazie o recipiente e acondicione vidro quebrado de forma segura para evitar acidentes.","special_waste":[],"variant_count":0}]'::jsonb) on conflict(object_id) do update set object_name=excluded.object_name, detection_class=excluded.detection_class, is_active=excluded.is_active, is_ambiguous=excluded.is_ambiguous, material_name=excluded.material_name, category_name=excluded.category_name, bin_name=excluded.bin_name, recommendation=excluded.recommendation, preparation_instructions=excluded.preparation_instructions, special_waste=excluded.special_waste, variant_count=excluded.variant_count;
insert into public.object_variants select * from jsonb_populate_recordset(null::public.object_variants, '[{"variant_id":1,"object_id":16,"material_name":"Plástico PET","category_name":"Plásticos","bin_name":"Vermelha","recommendation":"Esvazie a garrafa e descarte-a na coleta seletiva.","preparation_instructions":"Esvazie a embalagem e, quando possível, mantenha-a livre de restos de alimentos ou líquidos."},{"variant_id":4,"object_id":17,"material_name":"Plástico comum","category_name":"Plásticos","bin_name":"Vermelha","recommendation":"Encaminhe o plástico para a coleta seletiva.","preparation_instructions":"Sempre que possível, esvazie e limpe o excesso de conteúdo antes da coleta."},{"variant_id":6,"object_id":18,"material_name":"Plástico comum","category_name":"Plásticos","bin_name":"Vermelha","recommendation":"Encaminhe o plástico para a coleta seletiva.","preparation_instructions":"Sempre que possível, esvazie e limpe o excesso de conteúdo antes da coleta."},{"variant_id":8,"object_id":19,"material_name":"Plástico comum","category_name":"Plásticos","bin_name":"Vermelha","recommendation":"Encaminhe o plástico para a coleta seletiva.","preparation_instructions":"Sempre que possível, esvazie e limpe o excesso de conteúdo antes da coleta."},{"variant_id":2,"object_id":16,"material_name":"Vidro","category_name":"Vidros","bin_name":"Verde","recommendation":"Acondicione cuidadosamente o vidro quebrado para evitar acidentes.","preparation_instructions":"Esvazie o recipiente e acondicione vidro quebrado de forma segura para evitar acidentes."},{"variant_id":5,"object_id":17,"material_name":"Vidro","category_name":"Vidros","bin_name":"Verde","recommendation":"Acondicione cuidadosamente o vidro quebrado para evitar acidentes.","preparation_instructions":"Esvazie o recipiente e acondicione vidro quebrado de forma segura para evitar acidentes."},{"variant_id":7,"object_id":18,"material_name":"Vidro","category_name":"Vidros","bin_name":"Verde","recommendation":"Acondicione cuidadosamente o vidro quebrado para evitar acidentes.","preparation_instructions":"Esvazie o recipiente e acondicione vidro quebrado de forma segura para evitar acidentes."},{"variant_id":9,"object_id":19,"material_name":"Vidro","category_name":"Vidros","bin_name":"Verde","recommendation":"Acondicione cuidadosamente o vidro quebrado para evitar acidentes.","preparation_instructions":"Esvazie o recipiente e acondicione vidro quebrado de forma segura para evitar acidentes."},{"variant_id":3,"object_id":16,"material_name":"Aço","category_name":"Metais","bin_name":"Amarela","recommendation":"Retire o excesso de resíduos e encaminhe para a coleta seletiva.","preparation_instructions":"Retire o excesso de conteúdo e mantenha o material separado."}]'::jsonb) on conflict(variant_id) do update set object_id=excluded.object_id, material_name=excluded.material_name, category_name=excluded.category_name, bin_name=excluded.bin_name, recommendation=excluded.recommendation, preparation_instructions=excluded.preparation_instructions;
insert into public.object_aliases select * from jsonb_populate_recordset(null::public.object_aliases, '[{"object_id":16,"variant_id":1,"normalized_alias":"garrafa pet","is_active":true},{"object_id":16,"variant_id":1,"normalized_alias":"garrafa de pet","is_active":true},{"object_id":16,"variant_id":1,"normalized_alias":"pet","is_active":true},{"object_id":16,"variant_id":1,"normalized_alias":"garrafa plastica","is_active":true},{"object_id":16,"variant_id":1,"normalized_alias":"garrafa plástica","is_active":true},{"object_id":16,"variant_id":1,"normalized_alias":"garrafa de plástico","is_active":true},{"object_id":16,"variant_id":2,"normalized_alias":"garrafa de vidro","is_active":true},{"object_id":16,"variant_id":2,"normalized_alias":"garrafa vidro","is_active":true},{"object_id":16,"variant_id":2,"normalized_alias":"frasco de vidro","is_active":true},{"object_id":16,"variant_id":2,"normalized_alias":"vidro garrafa","is_active":true},{"object_id":16,"variant_id":3,"normalized_alias":"garrafa metal","is_active":true},{"object_id":16,"variant_id":3,"normalized_alias":"garrafa metálica","is_active":true},{"object_id":16,"variant_id":3,"normalized_alias":"garrafa de metal","is_active":true},{"object_id":16,"variant_id":3,"normalized_alias":"garrafa de aço","is_active":true},{"object_id":16,"variant_id":3,"normalized_alias":"garrafa termica","is_active":true},{"object_id":16,"variant_id":3,"normalized_alias":"garrafa térmica","is_active":true},{"object_id":35,"variant_id":null,"normalized_alias":"garrafa pet","is_active":true},{"object_id":35,"variant_id":null,"normalized_alias":"garrafa de pet","is_active":true},{"object_id":35,"variant_id":null,"normalized_alias":"garrafa plástica pet","is_active":true},{"object_id":36,"variant_id":null,"normalized_alias":"sacola plástica","is_active":true},{"object_id":36,"variant_id":null,"normalized_alias":"sacola de plástico","is_active":true},{"object_id":36,"variant_id":null,"normalized_alias":"sacola","is_active":true},{"object_id":37,"variant_id":null,"normalized_alias":"embalagem de plástico","is_active":true},{"object_id":37,"variant_id":null,"normalized_alias":"embalagem plástica","is_active":true},{"object_id":38,"variant_id":null,"normalized_alias":"shampoo bottle","is_active":true},{"object_id":38,"variant_id":null,"normalized_alias":"frasco de shampoo","is_active":true},{"object_id":38,"variant_id":null,"normalized_alias":"embalagem shampoo","is_active":true},{"object_id":39,"variant_id":null,"normalized_alias":"frasco detergente","is_active":true},{"object_id":39,"variant_id":null,"normalized_alias":"garrafa de detergente","is_active":true},{"object_id":40,"variant_id":null,"normalized_alias":"pote de plástico","is_active":true},{"object_id":40,"variant_id":null,"normalized_alias":"recipiente plástico","is_active":true},{"object_id":41,"variant_id":null,"normalized_alias":"pote de manteiga","is_active":true},{"object_id":41,"variant_id":null,"normalized_alias":"pote de margarina","is_active":true},{"object_id":42,"variant_id":null,"normalized_alias":"pote sorvete","is_active":true},{"object_id":43,"variant_id":null,"normalized_alias":"copo descartável","is_active":true},{"object_id":43,"variant_id":null,"normalized_alias":"copo plástico","is_active":true},{"object_id":43,"variant_id":null,"normalized_alias":"plastic cup","is_active":true},{"object_id":44,"variant_id":null,"normalized_alias":"tampa de plástico","is_active":true},{"object_id":44,"variant_id":null,"normalized_alias":"tampa plástica","is_active":true},{"object_id":45,"variant_id":null,"normalized_alias":"canudo","is_active":true},{"object_id":45,"variant_id":null,"normalized_alias":"canudo de plástico","is_active":true},{"object_id":46,"variant_id":null,"normalized_alias":"talher descartável","is_active":true},{"object_id":46,"variant_id":null,"normalized_alias":"talher de plástico","is_active":true},{"object_id":47,"variant_id":null,"normalized_alias":"filme pvc","is_active":true},{"object_id":47,"variant_id":null,"normalized_alias":"filme plástico","is_active":true},{"object_id":48,"variant_id":null,"normalized_alias":"galão de plástico","is_active":true},{"object_id":48,"variant_id":null,"normalized_alias":"galão plástico","is_active":true},{"object_id":49,"variant_id":null,"normalized_alias":"frasco de plástico","is_active":true},{"object_id":49,"variant_id":null,"normalized_alias":"recipiente plástico","is_active":true},{"object_id":50,"variant_id":null,"normalized_alias":"balde plástico","is_active":true},{"object_id":50,"variant_id":null,"normalized_alias":"balde de plástico","is_active":true},{"object_id":51,"variant_id":null,"normalized_alias":"bacia de plástico","is_active":true},{"object_id":52,"variant_id":null,"normalized_alias":"escova dental","is_active":true},{"object_id":52,"variant_id":null,"normalized_alias":"escova de dente","is_active":true},{"object_id":53,"variant_id":null,"normalized_alias":"pente","is_active":true},{"object_id":53,"variant_id":null,"normalized_alias":"pente plástico","is_active":true},{"object_id":54,"variant_id":null,"normalized_alias":"brinquedo de plástico","is_active":true},{"object_id":55,"variant_id":null,"normalized_alias":"mangueira de plástico","is_active":true},{"object_id":56,"variant_id":null,"normalized_alias":"tubo plástico","is_active":true},{"object_id":56,"variant_id":null,"normalized_alias":"tubulação de plástico","is_active":true},{"object_id":57,"variant_id":null,"normalized_alias":"caixa plástica","is_active":true},{"object_id":57,"variant_id":null,"normalized_alias":"organizador plástico","is_active":true},{"object_id":58,"variant_id":null,"normalized_alias":"pote cozinha","is_active":true},{"object_id":59,"variant_id":null,"normalized_alias":"embalagem de comida","is_active":true},{"object_id":59,"variant_id":null,"normalized_alias":"embalagem para alimento","is_active":true},{"object_id":60,"variant_id":null,"normalized_alias":"pacote de biscoito","is_active":true},{"object_id":61,"variant_id":null,"normalized_alias":"pacote de salgadinho","is_active":true},{"object_id":62,"variant_id":null,"normalized_alias":"pacote de arroz","is_active":true},{"object_id":63,"variant_id":null,"normalized_alias":"pacote de feijão","is_active":true},{"object_id":64,"variant_id":null,"normalized_alias":"saco de plástico","is_active":true},{"object_id":64,"variant_id":null,"normalized_alias":"sacolinha","is_active":true},{"object_id":65,"variant_id":null,"normalized_alias":"lacre","is_active":true},{"object_id":66,"variant_id":null,"normalized_alias":"pote cosmético","is_active":true},{"object_id":67,"variant_id":null,"normalized_alias":"frasco cosmético","is_active":true},{"object_id":68,"variant_id":null,"normalized_alias":"pote de creme","is_active":true},{"object_id":68,"variant_id":null,"normalized_alias":"embalagem de creme","is_active":true},{"object_id":69,"variant_id":null,"normalized_alias":"seringa","is_active":true},{"object_id":70,"variant_id":null,"normalized_alias":"folha","is_active":true},{"object_id":70,"variant_id":null,"normalized_alias":"folha de papel","is_active":true},{"object_id":71,"variant_id":null,"normalized_alias":"jornal","is_active":true},{"object_id":71,"variant_id":null,"normalized_alias":"newspaper","is_active":true},{"object_id":72,"variant_id":null,"normalized_alias":"revista","is_active":true},{"object_id":72,"variant_id":null,"normalized_alias":"magazine","is_active":true},{"object_id":73,"variant_id":null,"normalized_alias":"caderno","is_active":true},{"object_id":10,"variant_id":null,"normalized_alias":"livro","is_active":true},{"object_id":10,"variant_id":null,"normalized_alias":"book","is_active":true},{"object_id":75,"variant_id":null,"normalized_alias":"cartolina","is_active":true},{"object_id":76,"variant_id":null,"normalized_alias":"papelao","is_active":true},{"object_id":76,"variant_id":null,"normalized_alias":"papelão","is_active":true},{"object_id":77,"variant_id":null,"normalized_alias":"caixa de papelao","is_active":true},{"object_id":77,"variant_id":null,"normalized_alias":"caixa de papelão","is_active":true},{"object_id":77,"variant_id":null,"normalized_alias":"caixa de cartão","is_active":true},{"object_id":78,"variant_id":null,"normalized_alias":"caixa de cereal","is_active":true},{"object_id":78,"variant_id":null,"normalized_alias":"embalagem de cereal","is_active":true},{"object_id":79,"variant_id":null,"normalized_alias":"caixa de sapato","is_active":true},{"object_id":80,"variant_id":null,"normalized_alias":"caixa de mudança","is_active":true},{"object_id":80,"variant_id":null,"normalized_alias":"caixa de mudanca","is_active":true},{"object_id":81,"variant_id":null,"normalized_alias":"envelope","is_active":true},{"object_id":81,"variant_id":null,"normalized_alias":"envelope de papel","is_active":true},{"object_id":82,"variant_id":null,"normalized_alias":"saco de papel","is_active":true},{"object_id":82,"variant_id":null,"normalized_alias":"sacola de papel","is_active":true},{"object_id":83,"variant_id":null,"normalized_alias":"papel para presente","is_active":true},{"object_id":83,"variant_id":null,"normalized_alias":"papel presente","is_active":true},{"object_id":84,"variant_id":null,"normalized_alias":"papel embrulho","is_active":true},{"object_id":85,"variant_id":null,"normalized_alias":"papel impresso","is_active":true},{"object_id":86,"variant_id":null,"normalized_alias":"panfleto","is_active":true},{"object_id":86,"variant_id":null,"normalized_alias":"folheto","is_active":true},{"object_id":87,"variant_id":null,"normalized_alias":"folder","is_active":true},{"object_id":87,"variant_id":null,"normalized_alias":"folheto dobrável","is_active":true},{"object_id":88,"variant_id":null,"normalized_alias":"cartao","is_active":true},{"object_id":88,"variant_id":null,"normalized_alias":"cartão de papel","is_active":true},{"object_id":89,"variant_id":null,"normalized_alias":"cartao de visita","is_active":true},{"object_id":89,"variant_id":null,"normalized_alias":"cartão de visita","is_active":true},{"object_id":90,"variant_id":null,"normalized_alias":"poster","is_active":true},{"object_id":90,"variant_id":null,"normalized_alias":"cartaz","is_active":true},{"object_id":91,"variant_id":null,"normalized_alias":"apostila","is_active":true},{"object_id":92,"variant_id":null,"normalized_alias":"bilhete","is_active":true},{"object_id":92,"variant_id":null,"normalized_alias":"papel de anotação","is_active":true},{"object_id":93,"variant_id":null,"normalized_alias":"guardanapo","is_active":true},{"object_id":93,"variant_id":null,"normalized_alias":"guardanapo de papel","is_active":true},{"object_id":94,"variant_id":null,"normalized_alias":"toalha de papel","is_active":true},{"object_id":94,"variant_id":null,"normalized_alias":"papel toalha","is_active":true},{"object_id":95,"variant_id":null,"normalized_alias":"filtro de café","is_active":true},{"object_id":95,"variant_id":null,"normalized_alias":"filtro de papel","is_active":true},{"object_id":96,"variant_id":null,"normalized_alias":"papel a4","is_active":true},{"object_id":96,"variant_id":null,"normalized_alias":"papel de impressora","is_active":true},{"object_id":96,"variant_id":null,"normalized_alias":"folha a4","is_active":true},{"object_id":97,"variant_id":null,"normalized_alias":"folha de caderno","is_active":true},{"object_id":98,"variant_id":null,"normalized_alias":"papelão ondulado","is_active":true},{"object_id":99,"variant_id":null,"normalized_alias":"tubo de papelão","is_active":true},{"object_id":100,"variant_id":null,"normalized_alias":"rolo de papelão","is_active":true},{"object_id":101,"variant_id":null,"normalized_alias":"bandeja de papelão","is_active":true},{"object_id":102,"variant_id":null,"normalized_alias":"embalagem papel","is_active":true},{"object_id":102,"variant_id":null,"normalized_alias":"embalagem de papel","is_active":true},{"object_id":103,"variant_id":null,"normalized_alias":"embalagem papelão","is_active":true},{"object_id":103,"variant_id":null,"normalized_alias":"embalagem de papelao","is_active":true},{"object_id":104,"variant_id":null,"normalized_alias":"garrafa vidro","is_active":true},{"object_id":104,"variant_id":null,"normalized_alias":"garrafa de vidro","is_active":true},{"object_id":104,"variant_id":null,"normalized_alias":"glass bottle","is_active":true},{"object_id":105,"variant_id":null,"normalized_alias":"pote de vidro","is_active":true},{"object_id":105,"variant_id":null,"normalized_alias":"pote vidro","is_active":true},{"object_id":105,"variant_id":null,"normalized_alias":"glass jar","is_active":true},{"object_id":106,"variant_id":null,"normalized_alias":"pote conserva","is_active":true},{"object_id":106,"variant_id":null,"normalized_alias":"pote de conserva","is_active":true},{"object_id":106,"variant_id":null,"normalized_alias":"frasco de conserva","is_active":true},{"object_id":107,"variant_id":null,"normalized_alias":"frasco vidro","is_active":true},{"object_id":107,"variant_id":null,"normalized_alias":"frasco de vidro","is_active":true},{"object_id":107,"variant_id":null,"normalized_alias":"glass container","is_active":true},{"object_id":108,"variant_id":null,"normalized_alias":"frasco de perfume","is_active":true},{"object_id":108,"variant_id":null,"normalized_alias":"perfume bottle","is_active":true},{"object_id":108,"variant_id":null,"normalized_alias":"vidro perfume","is_active":true},{"object_id":109,"variant_id":null,"normalized_alias":"copo vidro","is_active":true},{"object_id":109,"variant_id":null,"normalized_alias":"copo de vidro","is_active":true},{"object_id":109,"variant_id":null,"normalized_alias":"glass cup","is_active":true},{"object_id":110,"variant_id":null,"normalized_alias":"taça vidro","is_active":true},{"object_id":110,"variant_id":null,"normalized_alias":"taça de vidro","is_active":true},{"object_id":110,"variant_id":null,"normalized_alias":"glass wine glass","is_active":true},{"object_id":111,"variant_id":null,"normalized_alias":"jarra vidro","is_active":true},{"object_id":111,"variant_id":null,"normalized_alias":"jarra de vidro","is_active":true},{"object_id":112,"variant_id":null,"normalized_alias":"travessa vidro","is_active":true},{"object_id":112,"variant_id":null,"normalized_alias":"travessa de vidro","is_active":true},{"object_id":113,"variant_id":null,"normalized_alias":"assadeira vidro","is_active":true},{"object_id":113,"variant_id":null,"normalized_alias":"assadeira de vidro","is_active":true},{"object_id":114,"variant_id":null,"normalized_alias":"pote hermético","is_active":true},{"object_id":114,"variant_id":null,"normalized_alias":"pote hermetico","is_active":true},{"object_id":114,"variant_id":null,"normalized_alias":"pote hermético de vidro","is_active":true},{"object_id":115,"variant_id":null,"normalized_alias":"recipiente vidro","is_active":true},{"object_id":115,"variant_id":null,"normalized_alias":"recipiente de vidro","is_active":true},{"object_id":116,"variant_id":null,"normalized_alias":"vidro conserva","is_active":true},{"object_id":116,"variant_id":null,"normalized_alias":"recipiente de conserva","is_active":true},{"object_id":117,"variant_id":null,"normalized_alias":"garrafa vinho","is_active":true},{"object_id":117,"variant_id":null,"normalized_alias":"garrafa de vinho","is_active":true},{"object_id":117,"variant_id":null,"normalized_alias":"wine bottle","is_active":true},{"object_id":118,"variant_id":null,"normalized_alias":"garrafa cerveja","is_active":true},{"object_id":118,"variant_id":null,"normalized_alias":"garrafa de cerveja","is_active":true},{"object_id":118,"variant_id":null,"normalized_alias":"beer bottle","is_active":true},{"object_id":119,"variant_id":null,"normalized_alias":"garrafa suco","is_active":true},{"object_id":119,"variant_id":null,"normalized_alias":"garrafa de suco","is_active":true},{"object_id":120,"variant_id":null,"normalized_alias":"garrafa refrigerante","is_active":true},{"object_id":120,"variant_id":null,"normalized_alias":"garrafa de refrigerante","is_active":true},{"object_id":121,"variant_id":null,"normalized_alias":"pote molho","is_active":true},{"object_id":121,"variant_id":null,"normalized_alias":"pote de molho","is_active":true},{"object_id":122,"variant_id":null,"normalized_alias":"pote geleia","is_active":true},{"object_id":122,"variant_id":null,"normalized_alias":"pote de geleia","is_active":true},{"object_id":123,"variant_id":null,"normalized_alias":"pote palmito","is_active":true},{"object_id":123,"variant_id":null,"normalized_alias":"pote de palmito","is_active":true},{"object_id":124,"variant_id":null,"normalized_alias":"pote azeitona","is_active":true},{"object_id":124,"variant_id":null,"normalized_alias":"pote de azeitona","is_active":true},{"object_id":125,"variant_id":null,"normalized_alias":"pote café","is_active":true},{"object_id":125,"variant_id":null,"normalized_alias":"pote de café","is_active":true},{"object_id":126,"variant_id":null,"normalized_alias":"pote tempero","is_active":true},{"object_id":126,"variant_id":null,"normalized_alias":"pote de tempero","is_active":true},{"object_id":127,"variant_id":null,"normalized_alias":"pote cozinha vidro","is_active":true},{"object_id":127,"variant_id":null,"normalized_alias":"pote de cozinha de vidro","is_active":true},{"object_id":128,"variant_id":null,"normalized_alias":"garrafa decorativa","is_active":true},{"object_id":128,"variant_id":null,"normalized_alias":"garrafa decorativa de vidro","is_active":true},{"object_id":129,"variant_id":null,"normalized_alias":"vaso vidro","is_active":true},{"object_id":129,"variant_id":null,"normalized_alias":"vaso de vidro","is_active":true},{"object_id":129,"variant_id":null,"normalized_alias":"glass vase","is_active":true},{"object_id":130,"variant_id":null,"normalized_alias":"objeto de vidro","is_active":true},{"object_id":130,"variant_id":null,"normalized_alias":"objeto decorativo vidro","is_active":true},{"object_id":131,"variant_id":null,"normalized_alias":"placa vidro","is_active":true},{"object_id":131,"variant_id":null,"normalized_alias":"placa de vidro","is_active":true},{"object_id":132,"variant_id":null,"normalized_alias":"tubo vidro","is_active":true},{"object_id":132,"variant_id":null,"normalized_alias":"tubo de vidro","is_active":true},{"object_id":133,"variant_id":null,"normalized_alias":"vidro embalagem","is_active":true},{"object_id":133,"variant_id":null,"normalized_alias":"vidro de embalagem","is_active":true},{"object_id":134,"variant_id":null,"normalized_alias":"embalagem vidro","is_active":true},{"object_id":134,"variant_id":null,"normalized_alias":"embalagem de vidro","is_active":true},{"object_id":21,"variant_id":null,"normalized_alias":"wireless mouse","is_active":true},{"object_id":21,"variant_id":null,"normalized_alias":"computer mouse","is_active":true},{"object_id":22,"variant_id":null,"normalized_alias":"keyboard","is_active":true},{"object_id":22,"variant_id":null,"normalized_alias":"computer keyboard","is_active":true},{"object_id":24,"variant_id":null,"normalized_alias":"tv","is_active":true},{"object_id":24,"variant_id":null,"normalized_alias":"television","is_active":true},{"object_id":25,"variant_id":null,"normalized_alias":"remote control","is_active":true}]'::jsonb) on conflict(object_id,variant_id,normalized_alias) do update set is_active=excluded.is_active;
-- <<< MIGRATION 202609290002_catalog.sql

-- >>> MIGRATION 202609290003_ecopoints.sql
-- 128 EcoPontos GeoSampa convertidos para WGS84.
insert into public.ecopoints(id,name,latitude,longitude,address,opening_hours,accepted_material_ids,accepted_materials_description,district,administrative_area,source,source_url) select id,name,latitude,longitude,address,opening_hours,accepted_material_ids,accepted_materials_description,district,administrative_area,source,source_url from jsonb_to_recordset('[{"id":"geosampa:1","name":"Bresser","latitude":-23.54340338,"longitude":-46.60646234,"address":"Praça Giuseppe Cesari, 54 (Baixos do Viaduto Bresser)","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Brás","administrative_area":"Mooca","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:2","name":"Pinheiros","latitude":-23.59791565,"longitude":-46.69133431,"address":"Praça do Cancioneiro, 15 (Baixos da Ponte Engenheiro Ary Torres)","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Itaim Bibi","administrative_area":"Pinheiros","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:3","name":"Tatuapé","latitude":-23.52948777,"longitude":-46.5833247,"address":"Avenida Salim Farah Maluf, 179, Praça Tito Lívio Ferreira (Central de Triagem)","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Tatuapé","administrative_area":"Mooca","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:5","name":"Cônego José Salomon","latitude":-23.49213174,"longitude":-46.72201391,"address":"Avenida Cônego José Salomon, 861","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Pirituba","administrative_area":"Pirituba-Jaraguá","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:6","name":"Viaduto Engenheiro Alberto Badra","latitude":-23.53714937,"longitude":-46.54739792,"address":"Avenida Aricanduva, 200, Praça Lúcia Mekhitarian (baixo do Viaduto Engenheiro Alberto Badra)","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Carrão","administrative_area":"Aricanduva","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:7","name":"Vigário Godói","latitude":-23.47760719,"longitude":-46.71820761,"address":"Rua Vigário Godói, 480","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Pirituba","administrative_area":"Pirituba-Jaraguá","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:10","name":"Mirandópolis","latitude":-23.6116377,"longitude":-46.6446815,"address":"Avenida Senador Casemiro da Rocha, 1220, esquina com Avenida José Maria Whitaker","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Saúde","administrative_area":"Vila Mariana","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:11","name":"Astarte ","latitude":-23.55005315,"longitude":-46.52504822,"address":"Rua Astarte, 500","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Carrão","administrative_area":"Aricanduva","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:12","name":"Bandeirantes ","latitude":-23.48630859,"longitude":-46.6950769,"address":"Rua Itaiquara, 237 - Travessa Avenida Itaberaba","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Freguesia Do Ó","administrative_area":"Freguesia-Brasilândia","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:15","name":"Vila Guilherme","latitude":-23.51713689,"longitude":-46.60041502,"address":"Rua José Bernardo Pinto, 1480","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Vila Guilherme","administrative_area":"Vila Maria-Vila Guilherme","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:19","name":"Parque Fernanda","latitude":-23.67182498,"longitude":-46.7922717,"address":"Avenida Doutor Salvador Rocco, 261, defronte Rua Antonio Cânon","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Capão Redondo","administrative_area":"Campo Limpo","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:23","name":"Anhaia Mello","latitude":-23.58256684,"longitude":-46.57117849,"address":"Rua da Prece, 296","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Vila Prudente","administrative_area":"Vila Prudente","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:24","name":"São Lucas","latitude":-23.59917252,"longitude":-46.53454286,"address":"Rua Florêncio Sanches, 307","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"São Lucas","administrative_area":"Vila Prudente","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:25","name":"Tereza Cristina ","latitude":-23.56913861,"longitude":-46.60852849,"address":"Avenida Teresa Cristina, 10 x Avenida do Estado","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Ipiranga","administrative_area":"Ipiranga","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:28","name":"Parque Guarani ","latitude":-23.52078451,"longitude":-46.46361279,"address":"Rua Manuel Alves da Rocha, 584","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Itaquera","administrative_area":"Itaquera","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:29","name":"Glicério","latitude":-23.55412195,"longitude":-46.62646319,"address":"Praça Ministro Francisco Sá Carneiro, 6 (Baixos do Viaduto Glicério, acesso pela Avenida do Estado, 4434)","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Sé","administrative_area":"Sé","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:33","name":"Vila Nova Cachoeirinha","latitude":-23.47212978,"longitude":-46.66979942,"address":"Rua Felix Alves Pereira, 113","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Cachoeirinha","administrative_area":"Casa Verde","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:36","name":"Tiquatira ","latitude":-23.51321978,"longitude":-46.54375268,"address":"Rua Amorim Diniz, 495","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Cangaíba","administrative_area":"Penha","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:37","name":"Vila Cardoso Franco ","latitude":-23.62326925,"longitude":-46.50909896,"address":"Rua dos Vorás, 25","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Sapopemba","administrative_area":"Sapopemba","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:39","name":"Vicente Rao","latitude":-23.62836639,"longitude":-46.68564954,"address":"Avenida Professor Vicente Rao, 308, sentido Diadema (Baixos do Viaduto Vereador José Diniz)","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Santo Amaro","administrative_area":"Santo Amaro","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:48","name":"Cambuci ","latitude":-23.56485941,"longitude":-46.61136516,"address":"Avenida Dom Pedro I, 38","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Cambuci","administrative_area":"Sé","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:50","name":"Imigrantes ","latitude":-23.63238705,"longitude":-46.63054387,"address":"Rua Opixe s/n","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Jabaquara","administrative_area":"Jabaquara","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:52","name":"Voith","latitude":-23.44514424,"longitude":-46.73981397,"address":"Avenida Atílio Brugnoli, 489","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Jaraguá","administrative_area":"Pirituba-Jaraguá","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:53","name":"Alexios Jafet ","latitude":-23.45301221,"longitude":-46.74968875,"address":"Avenida Alexios Jafet, 233","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Jaraguá","administrative_area":"Pirituba-Jaraguá","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:54","name":"Viaduto Antártica","latitude":-23.52436718,"longitude":-46.67063322,"address":"Rua Robert Bosch (Baixos Viaduto Antártica)","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Barra Funda","administrative_area":"Lapa","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:57","name":"Jardim Jaqueline ","latitude":-23.58938421,"longitude":-46.7550692,"address":"Parque Raposo Tavares","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Raposo Tavares","administrative_area":"Butantã","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:58","name":"Franquinho","latitude":-23.53218183,"longitude":-46.48748376,"address":"Rua Praia de Mucuripe, 685","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Artur Alvim","administrative_area":"Penha","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:62","name":"Cidade Saudável","latitude":-23.66226904,"longitude":-46.72232936,"address":"Rua Ptolomeu, 869","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Socorro","administrative_area":"Capela Do Socorro","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:64","name":"Alto de Pinheiros ","latitude":-23.55702395,"longitude":-46.71046986,"address":"Praça Arcipreste Anselmo de Oliveira","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Alto De Pinheiros","administrative_area":"Pinheiros","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:65","name":"Politécnica","latitude":-23.57586927,"longitude":-46.765178,"address":"Rua Paulino Baptista Conti, 2","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Rio Pequeno","administrative_area":"Butantã","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:66","name":"Osvaldo Valle Cordeiro","latitude":-23.55660145,"longitude":-46.49168811,"address":"Avenida Osvaldo Valle Cordeiro, 405","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Cidade Líder","administrative_area":"Itaquera","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:67","name":"Vila Luisa","latitude":-23.53118745,"longitude":-46.55247849,"address":"Praça Dante Maron, 92 (Baixos Viaduto Engenheiro Alberto Badra)","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Penha","administrative_area":"Penha","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:68","name":"Jardim Santa Fé","latitude":-23.43182355,"longitude":-46.79192145,"address":"Rua Salvador Albano, 156","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Anhanguera","administrative_area":"Perus-Anhanguera","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:69","name":"Vila das Belezas","latitude":-23.63804489,"longitude":-46.74156076,"address":"Rua Campo Novo do Sul, 500","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Vila Andrade","administrative_area":"Campo Limpo","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:70","name":"Água Rasa","latitude":-23.54374754,"longitude":-46.58057767,"address":"Avenida Salim Farah Maluf, 1500","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Belém","administrative_area":"Mooca","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:71","name":"Tucuruvi","latitude":-23.46741246,"longitude":-46.61016926,"address":"Rua Eduardo Vicente Nasser, 519","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Tucuruvi","administrative_area":"Santana-Tucuruvi","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:72","name":"Itaqueruna ","latitude":-23.51004341,"longitude":-46.43267625,"address":"Rua Domitilia d''Abril, 88","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"São Miguel","administrative_area":"São Miguel Paulista","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:74","name":"Freguesia do Ó","latitude":-23.50587435,"longitude":-46.70481562,"address":"Rua Sousa Filho, 690","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Freguesia Do Ó","administrative_area":"Freguesia-Brasilândia","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:76","name":"Guaiaponto ","latitude":-23.5553204,"longitude":-46.4132398,"address":"Rua da Passagem Funda, 250","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Guaianases","administrative_area":"Guaianases","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:77","name":"Jabaquara ","latitude":-23.6531483,"longitude":-46.6495108,"address":"Rua Jupatis, 140","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Jabaquara","administrative_area":"Jabaquara","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:79","name":"Santana ","latitude":-23.51115525,"longitude":-46.6214528,"address":"Avenida Zaki Narchi, 375","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Santana","administrative_area":"Santana-Tucuruvi","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:80","name":"Mãe Preta","latitude":-23.50839444,"longitude":-46.41689302,"address":"Avenida Dama Entre Verdes, 21","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Vila Curuçá","administrative_area":"Itaim Paulista","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:84","name":"Vila Mariana ","latitude":-23.59305472,"longitude":-46.63504142,"address":"Rua Mauricio Francisco Klabin, 37","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Vila Mariana","administrative_area":"Vila Mariana","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:90","name":"Piraporinha ","latitude":-23.66982945,"longitude":-46.73653365,"address":"Rua João de Abreu, 326","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Jardim São Luis","administrative_area":"M''Boi Mirim","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:92","name":"Montalvania ","latitude":-23.57934896,"longitude":-46.4953924,"address":"Rua Montalvania, 195","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"São Mateus","administrative_area":"São Mateus","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:97","name":"Corinthians ","latitude":-23.54791902,"longitude":-46.43705951,"address":"Rua Ana Perena, 155","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"José Bonifácio","administrative_area":"Itaquera","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:105","name":"Silvio Bittencourt","latitude":-23.45700093,"longitude":-46.58847969,"address":"Rua Maria Amália Lopes Azevedo, 4008","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Tremembé","administrative_area":"Jaçanã-Tremembé","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:106","name":"Vila Carmosina","latitude":-23.56281376,"longitude":-46.46539704,"address":"Avenida Francisco Tranchesi, 32 (altura)","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Parque Do Carmo","administrative_area":"Itaquera","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:107","name":"Condessa","latitude":-23.5277739,"longitude":-46.56842612,"address":"Avenida Condessa Elizabeth de Robiano, 930 (altura)","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Tatuapé","administrative_area":"Mooca","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:108","name":"Pedro Bueno","latitude":-23.63840164,"longitude":-46.6610746,"address":"Rua João de Lery, 503 (altura)","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Campo Belo","administrative_area":"Santo Amaro","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:111","name":"Geraldo Honório","latitude":-23.74778926,"longitude":-46.69296294,"address":"Rua Geraldo Honório da Silva, 280","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Grajaú","administrative_area":"Capela Do Socorro","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:112","name":"Vila Industrial","latitude":-23.60445684,"longitude":-46.53608968,"address":"Rua Lisa Ansorge, 645 (altura)","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"São Lucas","administrative_area":"Vila Prudente","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:114","name":"Anselmo Machado","latitude":-23.45891321,"longitude":-46.58570579,"address":"Avenida Paulo Lincoln do Valle Pontin, 550 (altura)","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Tremembé","administrative_area":"Jaçanã-Tremembé","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:115","name":"Vitor Manzini","latitude":-23.66068803,"longitude":-46.70549477,"address":"Praça Dom Francisco de Sousa, 635","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Santo Amaro","administrative_area":"Santo Amaro","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:116","name":"Aricanduva I","latitude":-23.58079181,"longitude":-46.5145184,"address":"Rua Professora Alzira Oliveira Gilioli, 400","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Aricanduva","administrative_area":"Aricanduva","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:122","name":"Mooca II","latitude":-23.5614094,"longitude":-46.56657311,"address":"Rua Pantojo, 1147","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Água Rasa","administrative_area":"Mooca","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:124","name":"Jardim Lapena","latitude":-23.49137823,"longitude":-46.45265167,"address":"Rua Rafael Zimbardi, 78 (altura)","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"São Miguel","administrative_area":"São Miguel Paulista","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:126","name":"Bela Vista","latitude":-23.55452657,"longitude":-46.64370208,"address":"Rua Quatorze de Julho, 59","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"República","administrative_area":"Sé","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:127","name":"Rubem Berta","latitude":-23.60224205,"longitude":-46.65109869,"address":"Avenida Rubem Berta, 1100 (baixo do Viaduto Onze de Junho)","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos · Gesso","district":"Moema","administrative_area":"Vila Mariana","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:4","name":"Imperador","latitude":-23.51391756,"longitude":-46.45666779,"address":"Avenida Ribeirão Jacu, 201 (Baixos do Viaduto Jacu Pêssego)","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Vila Jacuí","administrative_area":"São Miguel Paulista","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:8","name":"Penha I ","latitude":-23.53128019,"longitude":-46.52546966,"address":"Rua Doutor Heládio, 104","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Penha","administrative_area":"Penha","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:9","name":"Carlito Maia","latitude":-23.49008029,"longitude":-46.39353725,"address":"Rua Domingos Fernandes Nobre, 109","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Jardim Helena","administrative_area":"São Miguel Paulista","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:13","name":"Recanto dos Humildes","latitude":-23.40911172,"longitude":-46.7506729,"address":"Rua Salles Gomes, 415","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Perus","administrative_area":"Perus-Anhanguera","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:14","name":"Santo Dias ","latitude":-23.66393422,"longitude":-46.77678157,"address":"Travessa Rosifloras, 301","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Capão Redondo","administrative_area":"Campo Limpo","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:16","name":"Jardim Maria do Carmo","latitude":-23.59550532,"longitude":-46.74667865,"address":"Rua Caminho do Engenho, 800","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Vila Sônia","administrative_area":"Butantã","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:17","name":"Jardim São Nicolau","latitude":-23.52307578,"longitude":-46.48263444,"address":"Rua Agreste de Itabaiana, 590, esquina Rua Eduardo Kiyoshi Shimuta","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Ponte Rasa","administrative_area":"Ermelino Matarazzo","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:18","name":"Moreira ","latitude":-23.49748526,"longitude":-46.37089595,"address":"Rua João Batista de Godoy, 1164","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Itaim Paulista","administrative_area":"Itaim Paulista","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:20","name":"Nascer do Sol ","latitude":-23.59367758,"longitude":-46.41515726,"address":"Rua Nascer do Sol, 356","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Cidade Tiradentes","administrative_area":"Cidade Tiradentes","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:21","name":"Alceu Maynard de Araújo","latitude":-23.63607305,"longitude":-46.71379562,"address":"Avenida Professor Alceu Maynard de Araújo, 330, ao lado da Central de Triagem","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Santo Amaro","administrative_area":"Santo Amaro","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:22","name":"Cipoaba","latitude":-23.62932309,"longitude":-46.46220222,"address":"Rua Padre Luis de Siqueira, 947, com Avenida Rodolfo Pirani","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"São Rafael","administrative_area":"São Mateus","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:26","name":"Sapopemba ","latitude":-23.60556995,"longitude":-46.49691572,"address":"Rua Francesco Usper, 550","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Sapopemba","administrative_area":"Sapopemba","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:27","name":"Parque Peruche ","latitude":-23.49171361,"longitude":-46.65597969,"address":"Avenida Engenheiro Caetano Álvares, 3142","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Casa Verde","administrative_area":"Casa Verde","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:30","name":"Santa Cruz ","latitude":-23.59970707,"longitude":-46.62321068,"address":"Rua Santa Cruz, 1452 (Baixos Viaduto Santa Cruz)","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Cursino","administrative_area":"Ipiranga","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:31","name":"Vila Madalena ","latitude":-23.55826233,"longitude":-46.68733627,"address":"Rua Girassol, 15, esquina com Rua Luís Murat","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Pinheiros","administrative_area":"Pinheiros","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:32","name":"Pedro Nunes ","latitude":-23.50648884,"longitude":-46.46229337,"address":"Rua da Polka, 100","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Vila Jacuí","administrative_area":"São Miguel Paulista","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:34","name":"Vila Santa Maria ","latitude":-23.49401309,"longitude":-46.67155979,"address":"Rua André Bolsena x Travessa Luiz Sá","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Limão","administrative_area":"Casa Verde","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:35","name":"Jardim São Paulo ","latitude":-23.56538977,"longitude":-46.3984914,"address":"Rua Utaro Kanai, 374","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Guaianases","administrative_area":"Guaianases","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:38","name":"Alvarenga ","latitude":-23.69543603,"longitude":-46.65147728,"address":"Estrada do Alvarenga, 2475","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Pedreira","administrative_area":"Cidade Ademar","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:40","name":"Liberdade ","latitude":-23.55651997,"longitude":-46.63709904,"address":"Rua Jaceguai, 67, esquina com Avenida Liberdade","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Liberdade","administrative_area":"Sé","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:41","name":"Armênia ","latitude":-23.52142252,"longitude":-46.62775066,"address":"Rua General Carmona, 156","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Bom Retiro","administrative_area":"Sé","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:42","name":"Gamelinha","latitude":-23.55072846,"longitude":-46.49481348,"address":"Rua Morfeu, 25 x Avenida Edgar dos Santos","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Artur Alvim","administrative_area":"Penha","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:43","name":"Barra Funda","latitude":-23.52708624,"longitude":-46.64851396,"address":"Rua Cônego Vicente Miguel Marino, 76 (Baixos Viaduto Engenheiro Orlando Murgel)","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Santa Cecília","administrative_area":"Sé","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:44","name":"Cupecê","latitude":-23.66540629,"longitude":-46.65422699,"address":"Rua Anália Maria de Jesus, 130 - Travessa Avenida Cupecê","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Cidade Ademar","administrative_area":"Cidade Ademar","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:45","name":"Brás","latitude":-23.55450236,"longitude":-46.610758,"address":"Avenida Presidente Wilson, 1 (Baixo Viaduto Professor Alberto Mesquita de Carvalho)","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Brás","administrative_area":"Mooca","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:46","name":"Mooca","latitude":-23.54752322,"longitude":-46.60277055,"address":"Avenida Pires do Rio, 600 (Baixo Viaduto Bresser)","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Mooca","administrative_area":"Mooca","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:47","name":"Pari","latitude":-23.52444163,"longitude":-46.60936444,"address":"Avenida Carlos de Campos, 996, esquina com Avenida Presidente Castelo Branco","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Pari","administrative_area":"Mooca","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:49","name":"Vila Sabrina ","latitude":-23.48638492,"longitude":-46.5656272,"address":"Avenida dos Poetas, 931","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Vila Medeiros","administrative_area":"Vila Maria-Vila Guilherme","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:51","name":"Iguatemi","latitude":-23.60625788,"longitude":-46.45178854,"address":"Rua Francisco de Melo Palheta, 1548","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Iguatemi","administrative_area":"São Mateus","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:55","name":"Vila Matilde","latitude":-23.53923009,"longitude":-46.50518207,"address":"Rua Mateus de Siqueira, 375, com Praça Leonildes Ramos Saigo","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Vila Matilde","administrative_area":"Penha","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:56","name":"Cangaíba","latitude":-23.50392361,"longitude":-46.52758766,"address":"Rua Luciano Nogueira, 241, esquina com Rua Hugo Wolf","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Cangaíba","administrative_area":"Penha","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:59","name":"Olinda","latitude":-23.63414755,"longitude":-46.75803603,"address":"Rua Nelsom Brissac, 1235, esquina com Avenida Padre Adolfo Kolping","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Campo Limpo","administrative_area":"Campo Limpo","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:60","name":"Belém","latitude":-23.54324161,"longitude":-46.59391808,"address":"Rua Belarmino Matos, 26 (baixos do Viaduto Guadalajara)","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Belém","administrative_area":"Mooca","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:61","name":"Vila Maria ","latitude":-23.51972464,"longitude":-46.58082474,"address":"Rua Curuçá, 1700","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Vila Maria","administrative_area":"Vila Maria-Vila Guilherme","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:63","name":"Vila Jaguara","latitude":-23.51647874,"longitude":-46.74200639,"address":"Rua Agrestina, 189","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Jaguara","administrative_area":"Lapa","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:73","name":"Giovani Gronchi","latitude":-23.60993349,"longitude":-46.72681417,"address":"Avenida Giovani Gronchi, 3413","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Morumbi","administrative_area":"Butantã","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:75","name":"Nova York","latitude":-23.58763615,"longitude":-46.50905398,"address":"Rua Amália Vanso Magnoli, 480","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Aricanduva","administrative_area":"Aricanduva","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:78","name":"Vila Rica ","latitude":-23.46984812,"longitude":-46.67485774,"address":"Rua Jorge Mamede da Silva, 200","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Brasilândia","administrative_area":"Freguesia-Brasilândia","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:81","name":"Paraisópolis ","latitude":-23.62310137,"longitude":-46.72520717,"address":"Rua Irapará, 73","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Vila Andrade","administrative_area":"Campo Limpo","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:82","name":"Setor G","latitude":-23.58643063,"longitude":-46.39644443,"address":"Rua Alfonso Asturaro, 600 (altura)","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Cidade Tiradentes","administrative_area":"Cidade Tiradentes","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:83","name":"Pesqueiro ","latitude":-23.50124957,"longitude":-46.38938862,"address":"Rua Caiuas, 18 x Avenida Itamerendiba","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Itaim Paulista","administrative_area":"Itaim Paulista","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:85","name":"Saioa ","latitude":-23.59454966,"longitude":-46.62234416,"address":"Rua Mary Baida Salem, 1","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Vila Mariana","administrative_area":"Vila Mariana","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:86","name":"Vila das Mercês","latitude":-23.62379832,"longitude":-46.60553211,"address":"Rua Italva, 86","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Sacomã","administrative_area":"Ipiranga","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:87","name":"Cidade Lider ","latitude":-23.5627761,"longitude":-46.49717843,"address":"Rua Charles Manguin, 20","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Cidade Líder","administrative_area":"Itaquera","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:88","name":"Inácio Monteiro","latitude":-23.57340135,"longitude":-46.4013513,"address":"Rua Regresso Feliz, 1190","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Cidade Tiradentes","administrative_area":"Cidade Tiradentes","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:89","name":"Flamingo ","latitude":-23.51452624,"longitude":-46.42128077,"address":"Rua Alexandre Dias Nogueira, 353","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Vila Curuçá","administrative_area":"Itaim Paulista","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:91","name":"Mendes Caldeira","latitude":-23.53928252,"longitude":-46.62234212,"address":"Rua Monsenhor Andrade, 685","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Brás","administrative_area":"Mooca","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:93","name":"Jardim Antártica ","latitude":-23.45494801,"longitude":-46.65951212,"address":"Rua Dom Aquino, 309","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Cachoeirinha","administrative_area":"Casa Verde","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:94","name":"Boturussu ","latitude":-23.50382827,"longitude":-46.48494987,"address":"Rua Nélio Batista Guimarães, 183","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Ermelino Matarazzo","administrative_area":"Ermelino Matarazzo","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:95","name":"Comandante Taylor","latitude":-23.60012246,"longitude":-46.59727985,"address":"Rua Comandante Taylor, 690 (Baixos Viaduto Comandante Taylor)","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Ipiranga","administrative_area":"Ipiranga","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:96","name":"Parque do Carmo ","latitude":-23.57898094,"longitude":-46.48624485,"address":"Rua Machado Nunes, 95","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Parque Do Carmo","administrative_area":"Itaquera","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:98","name":"Dalila","latitude":-23.5505719,"longitude":-46.52230312,"address":"Rua Inácio da Costa, 740 x Avenida Aricanduva","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Vila Matilde","administrative_area":"Penha","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:99","name":"COHAB Artur Alvim","latitude":-23.54920087,"longitude":-46.48322901,"address":"Avenida Padre Estanislau de Campos, 56","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Artur Alvim","administrative_area":"Penha","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:100","name":"Vila Talarico","latitude":-23.53923497,"longitude":-46.51576487,"address":"Avenida Doutor Bernardino Brito Fonseca de Carvalho, 1050","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Vila Matilde","administrative_area":"Penha","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:101","name":"Lajeado ","latitude":-23.53093233,"longitude":-46.40618233,"address":"Rua Isabela, 405","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Lajeado","administrative_area":"Guaianases","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:102","name":"Lima Bonfante","latitude":-23.62838551,"longitude":-46.44632786,"address":"Rua Capitão Mor Lázaro da Costa, 251","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"São Rafael","administrative_area":"São Mateus","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:103","name":"Varre Vila","latitude":-23.48766599,"longitude":-46.45866749,"address":"Rua Primeiro de Maio, 106 (defronte)","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Vila Jacuí","administrative_area":"São Miguel Paulista","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:104","name":"Vitória Popular","latitude":-23.50937414,"longitude":-46.47231119,"address":"Rua El Rey, 526","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Vila Jacuí","administrative_area":"São Miguel Paulista","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:109","name":"Reynaldo José","latitude":-23.60741897,"longitude":-46.5177184,"address":"Rua Silvestro Silvestri, 400","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Sapopemba","administrative_area":"Sapopemba","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:110","name":"São Luis","latitude":-23.66667354,"longitude":-46.74556176,"address":"Rua Pedro Armani, 252","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Jardim São Luis","administrative_area":"M''Boi Mirim","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:113","name":"Jardim Helena","latitude":-23.47990648,"longitude":-46.41193272,"address":"Rua Cosme dos Santos, 110 (defronte)","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Jardim Helena","administrative_area":"São Miguel Paulista","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:117","name":"São Leandro","latitude":-23.49659996,"longitude":-46.68380831,"address":"Rua São Leandro, 13","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Limão","administrative_area":"Casa Verde","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:118","name":"Padre Nildo do Amaral","latitude":-23.52072432,"longitude":-46.42891494,"address":"Rua Padre Nildo do Amaral Junior, 900","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Lajeado","administrative_area":"Guaianases","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:119","name":"Caldeirão","latitude":-23.53756543,"longitude":-46.43179796,"address":"Rua Major Vitorino de Souza Rocha, 148 (altura)","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"José Bonifácio","administrative_area":"Itaquera","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:120","name":"Itaim Paulista","latitude":-23.50466316,"longitude":-46.37266161,"address":"Rua Barão Almeida Galeão, 61 (altura)","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Itaim Paulista","administrative_area":"Itaim Paulista","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:121","name":"Jardim Indaiá","latitude":-23.51600617,"longitude":-46.3943328,"address":"Rua Rossini Pinto, 214 (altura)","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Itaim Paulista","administrative_area":"Itaim Paulista","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:123","name":"Jardim Romano","latitude":-23.47813908,"longitude":-46.38311894,"address":"Rua Duarte Martins Mourão, 400","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Jardim Helena","administrative_area":"São Miguel Paulista","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:125","name":"Joaquim Catuna","latitude":-23.61955954,"longitude":-46.48878768,"address":"Rua Luca Conforti, 210","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Sapopemba","administrative_area":"Sapopemba","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"},{"id":"geosampa:128","name":"Vida Nova","latitude":-23.5860221,"longitude":-46.80035258,"address":"Travessa Córrego Independência, 2","opening_hours":"segunda a sábado, das 6h às 22h; domingo e feriado, das 6h às 18h","accepted_material_ids":["glass","metal","paper","plastic","special"],"accepted_materials_description":"Entulho, volumosos, restos de poda e recicláveis secos","district":"Raposo Tavares","administrative_area":"Butantã","source":"geosampa","source_url":"https://geosampa.prefeitura.sp.gov.br/"}]'::jsonb) as x(id text,name text,latitude double precision,longitude double precision,address text,opening_hours text,accepted_material_ids text[],accepted_materials_description text,district text,administrative_area text,source text,source_url text) on conflict(id) do update set name=excluded.name,latitude=excluded.latitude,longitude=excluded.longitude,address=excluded.address,opening_hours=excluded.opening_hours,accepted_material_ids=excluded.accepted_material_ids,accepted_materials_description=excluded.accepted_materials_description,district=excluded.district,administrative_area=excluded.administrative_area,source=excluded.source,source_url=excluded.source_url,updated_at=now(),is_active=true;
update public.ecopoints set is_active=false, updated_at=now() where source='geosampa' and id not in ('geosampa:1','geosampa:2','geosampa:3','geosampa:5','geosampa:6','geosampa:7','geosampa:10','geosampa:11','geosampa:12','geosampa:15','geosampa:19','geosampa:23','geosampa:24','geosampa:25','geosampa:28','geosampa:29','geosampa:33','geosampa:36','geosampa:37','geosampa:39','geosampa:48','geosampa:50','geosampa:52','geosampa:53','geosampa:54','geosampa:57','geosampa:58','geosampa:62','geosampa:64','geosampa:65','geosampa:66','geosampa:67','geosampa:68','geosampa:69','geosampa:70','geosampa:71','geosampa:72','geosampa:74','geosampa:76','geosampa:77','geosampa:79','geosampa:80','geosampa:84','geosampa:90','geosampa:92','geosampa:97','geosampa:105','geosampa:106','geosampa:107','geosampa:108','geosampa:111','geosampa:112','geosampa:114','geosampa:115','geosampa:116','geosampa:122','geosampa:124','geosampa:126','geosampa:127','geosampa:4','geosampa:8','geosampa:9','geosampa:13','geosampa:14','geosampa:16','geosampa:17','geosampa:18','geosampa:20','geosampa:21','geosampa:22','geosampa:26','geosampa:27','geosampa:30','geosampa:31','geosampa:32','geosampa:34','geosampa:35','geosampa:38','geosampa:40','geosampa:41','geosampa:42','geosampa:43','geosampa:44','geosampa:45','geosampa:46','geosampa:47','geosampa:49','geosampa:51','geosampa:55','geosampa:56','geosampa:59','geosampa:60','geosampa:61','geosampa:63','geosampa:73','geosampa:75','geosampa:78','geosampa:81','geosampa:82','geosampa:83','geosampa:85','geosampa:86','geosampa:87','geosampa:88','geosampa:89','geosampa:91','geosampa:93','geosampa:94','geosampa:95','geosampa:96','geosampa:98','geosampa:99','geosampa:100','geosampa:101','geosampa:102','geosampa:103','geosampa:104','geosampa:109','geosampa:110','geosampa:113','geosampa:117','geosampa:118','geosampa:119','geosampa:120','geosampa:121','geosampa:123','geosampa:125','geosampa:128');
-- <<< MIGRATION 202609290003_ecopoints.sql

-- >>> MIGRATION 202609300001_yoloe_catalog.sql
-- Prompts YOLOE; executar após as migrations 20260929.
-- Uma transação preserva a consistência entre objetos e aliases.
update public.objects set detection_class = null where object_id < 10000 and detection_class in (select value from jsonb_array_elements_text('["plastic bottle", "glass bottle", "aluminum can", "steel can", "cardboard box", "cardboard", "paper", "newspaper", "magazine", "book", "envelope", "plastic bag", "paper bag", "plastic cup", "paper cup", "glass jar", "plastic container", "food container", "beverage carton", "aerosol can", "battery", "car battery", "light bulb", "fluorescent lamp", "smartphone", "tablet", "laptop", "computer monitor", "computer keyboard", "computer mouse", "printer", "television", "phone charger", "power cable", "headphones", "earphones", "circuit board", "router", "power bank", "electronic device", "camera", "speaker", "game controller", "remote control", "microwave oven", "refrigerator", "washing machine", "tire", "clothing", "shoe", "medicine blister pack", "cooking oil bottle", "food waste", "metal container", "plastic wrapper", "detergent bottle", "shampoo bottle"]'::jsonb));
delete from public.object_aliases where normalized_alias in (select value from jsonb_array_elements_text('["aerosol can", "aluminum can", "battery", "beverage carton", "book", "camera", "car battery", "cardboard", "cardboard box", "circuit board", "clothing", "computer keyboard", "computer monitor", "computer mouse", "cooking oil bottle", "detergent bottle", "earphones", "electronic device", "envelope", "fluorescent lamp", "food container", "food waste", "game controller", "glass bottle", "glass jar", "headphones", "laptop", "light bulb", "magazine", "medicine blister pack", "metal container", "microwave oven", "newspaper", "paper", "paper bag", "paper cup", "phone charger", "plastic bag", "plastic bottle", "plastic container", "plastic cup", "plastic wrapper", "power bank", "power cable", "printer", "refrigerator", "remote control", "router", "shampoo bottle", "shoe", "smartphone", "speaker", "steel can", "tablet", "television", "tire", "washing machine"]'::jsonb));
insert into public.objects select * from jsonb_populate_recordset(null::public.objects, '[{"object_id": 10000, "object_name": "Garrafa plástica", "detection_class": "plastic bottle", "is_active": true, "is_ambiguous": false, "material_name": "Plástico", "category_name": "Plástico", "bin_name": "Vermelha", "recommendation": "Esvazie, retire o excesso de resíduos e confirme o tipo de plástico aceito na coleta seletiva local.", "preparation_instructions": "Esvazie, retire o excesso de resíduos e confirme o tipo de plástico aceito na coleta seletiva local.", "special_waste": [], "variant_count": 0}, {"object_id": 10001, "object_name": "Garrafa de vidro", "detection_class": "glass bottle", "is_active": true, "is_ambiguous": false, "material_name": "Vidro", "category_name": "Vidro", "bin_name": "Verde", "recommendation": "Esvazie. Proteja e identifique cacos antes de entregar à coleta de vidro.", "preparation_instructions": "Esvazie. Proteja e identifique cacos antes de entregar à coleta de vidro.", "special_waste": [], "variant_count": 0}, {"object_id": 10002, "object_name": "Lata de alumínio", "detection_class": "aluminum can", "is_active": true, "is_ambiguous": false, "material_name": "Metal", "category_name": "Metal", "bin_name": "Amarela", "recommendation": "Esvazie, retire o excesso de resíduos e encaminhe para a coleta de metais aceita localmente.", "preparation_instructions": "Esvazie, retire o excesso de resíduos e encaminhe para a coleta de metais aceita localmente.", "special_waste": [], "variant_count": 0}, {"object_id": 10003, "object_name": "Lata de aço", "detection_class": "steel can", "is_active": true, "is_ambiguous": false, "material_name": "Metal", "category_name": "Metal", "bin_name": "Amarela", "recommendation": "Esvazie, retire o excesso de resíduos e encaminhe para a coleta de metais aceita localmente.", "preparation_instructions": "Esvazie, retire o excesso de resíduos e encaminhe para a coleta de metais aceita localmente.", "special_waste": [], "variant_count": 0}, {"object_id": 10004, "object_name": "Caixa de papelão", "detection_class": "cardboard box", "is_active": true, "is_ambiguous": false, "material_name": "Papel", "category_name": "Papel", "bin_name": "Azul", "recommendation": "Mantenha seco e sem restos de alimentos. Papéis revestidos ou contaminados podem exigir outro destino; confirme a coleta local.", "preparation_instructions": "Mantenha seco e sem restos de alimentos. Papéis revestidos ou contaminados podem exigir outro destino; confirme a coleta local.", "special_waste": [], "variant_count": 0}, {"object_id": 10005, "object_name": "Papelão", "detection_class": "cardboard", "is_active": true, "is_ambiguous": false, "material_name": "Papel", "category_name": "Papel", "bin_name": "Azul", "recommendation": "Mantenha seco e sem restos de alimentos. Papéis revestidos ou contaminados podem exigir outro destino; confirme a coleta local.", "preparation_instructions": "Mantenha seco e sem restos de alimentos. Papéis revestidos ou contaminados podem exigir outro destino; confirme a coleta local.", "special_waste": [], "variant_count": 0}, {"object_id": 10006, "object_name": "Papel", "detection_class": "paper", "is_active": true, "is_ambiguous": false, "material_name": "Papel", "category_name": "Papel", "bin_name": "Azul", "recommendation": "Mantenha seco e sem restos de alimentos. Papéis revestidos ou contaminados podem exigir outro destino; confirme a coleta local.", "preparation_instructions": "Mantenha seco e sem restos de alimentos. Papéis revestidos ou contaminados podem exigir outro destino; confirme a coleta local.", "special_waste": [], "variant_count": 0}, {"object_id": 10007, "object_name": "Jornal", "detection_class": "newspaper", "is_active": true, "is_ambiguous": false, "material_name": "Papel", "category_name": "Papel", "bin_name": "Azul", "recommendation": "Mantenha seco e sem restos de alimentos. Papéis revestidos ou contaminados podem exigir outro destino; confirme a coleta local.", "preparation_instructions": "Mantenha seco e sem restos de alimentos. Papéis revestidos ou contaminados podem exigir outro destino; confirme a coleta local.", "special_waste": [], "variant_count": 0}, {"object_id": 10008, "object_name": "Revista", "detection_class": "magazine", "is_active": true, "is_ambiguous": false, "material_name": "Papel", "category_name": "Papel", "bin_name": "Azul", "recommendation": "Mantenha seco e sem restos de alimentos. Papéis revestidos ou contaminados podem exigir outro destino; confirme a coleta local.", "preparation_instructions": "Mantenha seco e sem restos de alimentos. Papéis revestidos ou contaminados podem exigir outro destino; confirme a coleta local.", "special_waste": [], "variant_count": 0}, {"object_id": 10009, "object_name": "Livro", "detection_class": "book", "is_active": true, "is_ambiguous": false, "material_name": "Papel", "category_name": "Papel", "bin_name": "Azul", "recommendation": "Mantenha seco e sem restos de alimentos. Papéis revestidos ou contaminados podem exigir outro destino; confirme a coleta local.", "preparation_instructions": "Mantenha seco e sem restos de alimentos. Papéis revestidos ou contaminados podem exigir outro destino; confirme a coleta local.", "special_waste": [], "variant_count": 0}, {"object_id": 10010, "object_name": "Envelope", "detection_class": "envelope", "is_active": true, "is_ambiguous": false, "material_name": "Papel", "category_name": "Papel", "bin_name": "Azul", "recommendation": "Mantenha seco e sem restos de alimentos. Papéis revestidos ou contaminados podem exigir outro destino; confirme a coleta local.", "preparation_instructions": "Mantenha seco e sem restos de alimentos. Papéis revestidos ou contaminados podem exigir outro destino; confirme a coleta local.", "special_waste": [], "variant_count": 0}, {"object_id": 10011, "object_name": "Sacola plástica", "detection_class": "plastic bag", "is_active": true, "is_ambiguous": false, "material_name": "Plástico", "category_name": "Plástico", "bin_name": "Vermelha", "recommendation": "Esvazie, retire o excesso de resíduos e confirme o tipo de plástico aceito na coleta seletiva local.", "preparation_instructions": "Esvazie, retire o excesso de resíduos e confirme o tipo de plástico aceito na coleta seletiva local.", "special_waste": [], "variant_count": 0}, {"object_id": 10012, "object_name": "Sacola de papel", "detection_class": "paper bag", "is_active": true, "is_ambiguous": false, "material_name": "Papel", "category_name": "Papel", "bin_name": "Azul", "recommendation": "Mantenha seco e sem restos de alimentos. Papéis revestidos ou contaminados podem exigir outro destino; confirme a coleta local.", "preparation_instructions": "Mantenha seco e sem restos de alimentos. Papéis revestidos ou contaminados podem exigir outro destino; confirme a coleta local.", "special_waste": [], "variant_count": 0}, {"object_id": 10013, "object_name": "Copo plástico", "detection_class": "plastic cup", "is_active": true, "is_ambiguous": false, "material_name": "Plástico", "category_name": "Plástico", "bin_name": "Vermelha", "recommendation": "Esvazie, retire o excesso de resíduos e confirme o tipo de plástico aceito na coleta seletiva local.", "preparation_instructions": "Esvazie, retire o excesso de resíduos e confirme o tipo de plástico aceito na coleta seletiva local.", "special_waste": [], "variant_count": 0}, {"object_id": 10014, "object_name": "Copo de papel", "detection_class": "paper cup", "is_active": true, "is_ambiguous": false, "material_name": "Papel", "category_name": "Papel", "bin_name": "Azul", "recommendation": "Mantenha seco e sem restos de alimentos. Papéis revestidos ou contaminados podem exigir outro destino; confirme a coleta local.", "preparation_instructions": "Mantenha seco e sem restos de alimentos. Papéis revestidos ou contaminados podem exigir outro destino; confirme a coleta local.", "special_waste": [], "variant_count": 0}, {"object_id": 10015, "object_name": "Pote de vidro", "detection_class": "glass jar", "is_active": true, "is_ambiguous": false, "material_name": "Vidro", "category_name": "Vidro", "bin_name": "Verde", "recommendation": "Esvazie. Proteja e identifique cacos antes de entregar à coleta de vidro.", "preparation_instructions": "Esvazie. Proteja e identifique cacos antes de entregar à coleta de vidro.", "special_waste": [], "variant_count": 0}, {"object_id": 10016, "object_name": "Recipiente plástico", "detection_class": "plastic container", "is_active": true, "is_ambiguous": false, "material_name": "Plástico", "category_name": "Plástico", "bin_name": "Vermelha", "recommendation": "Esvazie, retire o excesso de resíduos e confirme o tipo de plástico aceito na coleta seletiva local.", "preparation_instructions": "Esvazie, retire o excesso de resíduos e confirme o tipo de plástico aceito na coleta seletiva local.", "special_waste": [], "variant_count": 0}, {"object_id": 10017, "object_name": "Recipiente de alimentos", "detection_class": "food container", "is_active": true, "is_ambiguous": true, "material_name": null, "category_name": null, "bin_name": null, "recommendation": "O recipiente pode ser de plástico, vidro ou metal. Aproxime apenas o objeto e tire outra foto para identificar o material.", "preparation_instructions": "O recipiente pode ser de plástico, vidro ou metal. Aproxime apenas o objeto e tire outra foto para identificar o material.", "special_waste": [], "variant_count": 0}, {"object_id": 10018, "object_name": "Embalagem longa vida", "detection_class": "beverage carton", "is_active": true, "is_ambiguous": false, "material_name": "Descarte especial", "category_name": "Descarte especial", "bin_name": "Coleta especial", "recommendation": "Embalagem multicamadas. Esvazie e encaminhe à coleta seletiva que aceite embalagens longa vida na sua cidade.", "preparation_instructions": "Embalagem multicamadas. Esvazie e encaminhe à coleta seletiva que aceite embalagens longa vida na sua cidade.", "special_waste": ["Descarte especial"], "variant_count": 0}, {"object_id": 10019, "object_name": "Lata de aerossol", "detection_class": "aerosol can", "is_active": true, "is_ambiguous": false, "material_name": "Descarte especial", "category_name": "Descarte especial", "bin_name": "Coleta especial", "recommendation": "Não perfure nem queime. Confirme a coleta de aerossóis e embalagens pressurizadas no ponto de recebimento.", "preparation_instructions": "Não perfure nem queime. Confirme a coleta de aerossóis e embalagens pressurizadas no ponto de recebimento.", "special_waste": ["Descarte especial"], "variant_count": 0}, {"object_id": 10020, "object_name": "Pilha ou bateria", "detection_class": "battery", "is_active": true, "is_ambiguous": false, "material_name": "Descarte especial", "category_name": "Descarte especial", "bin_name": "Coleta especial", "recommendation": "Proteja os terminais contra curto-circuito. Entregue em coleta específica de pilhas e baterias; não coloque na coleta comum.", "preparation_instructions": "Proteja os terminais contra curto-circuito. Entregue em coleta específica de pilhas e baterias; não coloque na coleta comum.", "special_waste": ["Descarte especial"], "variant_count": 0}, {"object_id": 10021, "object_name": "Bateria automotiva", "detection_class": "car battery", "is_active": true, "is_ambiguous": false, "material_name": "Descarte especial", "category_name": "Descarte especial", "bin_name": "Coleta especial", "recommendation": "Proteja os terminais contra curto-circuito. Entregue em coleta específica de pilhas e baterias; não coloque na coleta comum.", "preparation_instructions": "Proteja os terminais contra curto-circuito. Entregue em coleta específica de pilhas e baterias; não coloque na coleta comum.", "special_waste": ["Descarte especial"], "variant_count": 0}, {"object_id": 10022, "object_name": "Lâmpada", "detection_class": "light bulb", "is_active": true, "is_ambiguous": false, "material_name": "Descarte especial", "category_name": "Descarte especial", "bin_name": "Coleta especial", "recommendation": "Evite quebrar. Entregue em um ponto que aceite esse tipo de lâmpada; não descarte na coleta de vidro.", "preparation_instructions": "Evite quebrar. Entregue em um ponto que aceite esse tipo de lâmpada; não descarte na coleta de vidro.", "special_waste": ["Descarte especial"], "variant_count": 0}, {"object_id": 10023, "object_name": "Lâmpada fluorescente", "detection_class": "fluorescent lamp", "is_active": true, "is_ambiguous": false, "material_name": "Descarte especial", "category_name": "Descarte especial", "bin_name": "Coleta especial", "recommendation": "Evite quebrar. Entregue em um ponto que aceite esse tipo de lâmpada; não descarte na coleta de vidro.", "preparation_instructions": "Evite quebrar. Entregue em um ponto que aceite esse tipo de lâmpada; não descarte na coleta de vidro.", "special_waste": ["Descarte especial"], "variant_count": 0}, {"object_id": 10024, "object_name": "Celular", "detection_class": "smartphone", "is_active": true, "is_ambiguous": false, "material_name": "Eletrônico", "category_name": "Eletrônico", "bin_name": "Coleta especial", "recommendation": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "preparation_instructions": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "special_waste": ["Eletrônico"], "variant_count": 0}, {"object_id": 10025, "object_name": "Tablet", "detection_class": "tablet", "is_active": true, "is_ambiguous": false, "material_name": "Eletrônico", "category_name": "Eletrônico", "bin_name": "Coleta especial", "recommendation": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "preparation_instructions": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "special_waste": ["Eletrônico"], "variant_count": 0}, {"object_id": 10026, "object_name": "Notebook", "detection_class": "laptop", "is_active": true, "is_ambiguous": false, "material_name": "Eletrônico", "category_name": "Eletrônico", "bin_name": "Coleta especial", "recommendation": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "preparation_instructions": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "special_waste": ["Eletrônico"], "variant_count": 0}, {"object_id": 10027, "object_name": "Monitor", "detection_class": "computer monitor", "is_active": true, "is_ambiguous": false, "material_name": "Eletrônico", "category_name": "Eletrônico", "bin_name": "Coleta especial", "recommendation": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "preparation_instructions": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "special_waste": ["Eletrônico"], "variant_count": 0}, {"object_id": 10028, "object_name": "Teclado", "detection_class": "computer keyboard", "is_active": true, "is_ambiguous": false, "material_name": "Eletrônico", "category_name": "Eletrônico", "bin_name": "Coleta especial", "recommendation": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "preparation_instructions": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "special_waste": ["Eletrônico"], "variant_count": 0}, {"object_id": 10029, "object_name": "Mouse", "detection_class": "computer mouse", "is_active": true, "is_ambiguous": false, "material_name": "Eletrônico", "category_name": "Eletrônico", "bin_name": "Coleta especial", "recommendation": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "preparation_instructions": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "special_waste": ["Eletrônico"], "variant_count": 0}, {"object_id": 10030, "object_name": "Impressora", "detection_class": "printer", "is_active": true, "is_ambiguous": false, "material_name": "Eletrônico", "category_name": "Eletrônico", "bin_name": "Coleta especial", "recommendation": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "preparation_instructions": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "special_waste": ["Eletrônico"], "variant_count": 0}, {"object_id": 10031, "object_name": "Televisão", "detection_class": "television", "is_active": true, "is_ambiguous": false, "material_name": "Eletrônico", "category_name": "Eletrônico", "bin_name": "Coleta especial", "recommendation": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "preparation_instructions": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "special_waste": ["Eletrônico"], "variant_count": 0}, {"object_id": 10032, "object_name": "Carregador", "detection_class": "phone charger", "is_active": true, "is_ambiguous": false, "material_name": "Eletrônico", "category_name": "Eletrônico", "bin_name": "Coleta especial", "recommendation": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "preparation_instructions": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "special_waste": ["Eletrônico"], "variant_count": 0}, {"object_id": 10033, "object_name": "Cabo elétrico", "detection_class": "power cable", "is_active": true, "is_ambiguous": false, "material_name": "Eletrônico", "category_name": "Eletrônico", "bin_name": "Coleta especial", "recommendation": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "preparation_instructions": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "special_waste": ["Eletrônico"], "variant_count": 0}, {"object_id": 10034, "object_name": "Fone de ouvido", "detection_class": "headphones", "is_active": true, "is_ambiguous": false, "material_name": "Eletrônico", "category_name": "Eletrônico", "bin_name": "Coleta especial", "recommendation": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "preparation_instructions": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "special_waste": ["Eletrônico"], "variant_count": 0}, {"object_id": 10035, "object_name": "Fone de ouvido", "detection_class": "earphones", "is_active": true, "is_ambiguous": false, "material_name": "Eletrônico", "category_name": "Eletrônico", "bin_name": "Coleta especial", "recommendation": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "preparation_instructions": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "special_waste": ["Eletrônico"], "variant_count": 0}, {"object_id": 10036, "object_name": "Placa eletrônica", "detection_class": "circuit board", "is_active": true, "is_ambiguous": false, "material_name": "Eletrônico", "category_name": "Eletrônico", "bin_name": "Coleta especial", "recommendation": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "preparation_instructions": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "special_waste": ["Eletrônico"], "variant_count": 0}, {"object_id": 10037, "object_name": "Roteador", "detection_class": "router", "is_active": true, "is_ambiguous": false, "material_name": "Eletrônico", "category_name": "Eletrônico", "bin_name": "Coleta especial", "recommendation": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "preparation_instructions": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "special_waste": ["Eletrônico"], "variant_count": 0}, {"object_id": 10038, "object_name": "Bateria portátil", "detection_class": "power bank", "is_active": true, "is_ambiguous": false, "material_name": "Eletrônico", "category_name": "Eletrônico", "bin_name": "Coleta especial", "recommendation": "Proteja os terminais contra curto-circuito. Entregue em coleta específica de pilhas e baterias; não coloque na coleta comum.", "preparation_instructions": "Proteja os terminais contra curto-circuito. Entregue em coleta específica de pilhas e baterias; não coloque na coleta comum.", "special_waste": ["Eletrônico"], "variant_count": 0}, {"object_id": 10039, "object_name": "Aparelho eletrônico", "detection_class": "electronic device", "is_active": true, "is_ambiguous": false, "material_name": "Eletrônico", "category_name": "Eletrônico", "bin_name": "Coleta especial", "recommendation": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "preparation_instructions": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "special_waste": ["Eletrônico"], "variant_count": 0}, {"object_id": 10040, "object_name": "Câmera", "detection_class": "camera", "is_active": true, "is_ambiguous": false, "material_name": "Eletrônico", "category_name": "Eletrônico", "bin_name": "Coleta especial", "recommendation": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "preparation_instructions": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "special_waste": ["Eletrônico"], "variant_count": 0}, {"object_id": 10041, "object_name": "Caixa de som", "detection_class": "speaker", "is_active": true, "is_ambiguous": false, "material_name": "Eletrônico", "category_name": "Eletrônico", "bin_name": "Coleta especial", "recommendation": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "preparation_instructions": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "special_waste": ["Eletrônico"], "variant_count": 0}, {"object_id": 10042, "object_name": "Controle de videogame", "detection_class": "game controller", "is_active": true, "is_ambiguous": false, "material_name": "Eletrônico", "category_name": "Eletrônico", "bin_name": "Coleta especial", "recommendation": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "preparation_instructions": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "special_waste": ["Eletrônico"], "variant_count": 0}, {"object_id": 10043, "object_name": "Controle remoto", "detection_class": "remote control", "is_active": true, "is_ambiguous": false, "material_name": "Eletrônico", "category_name": "Eletrônico", "bin_name": "Coleta especial", "recommendation": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "preparation_instructions": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "special_waste": ["Eletrônico"], "variant_count": 0}, {"object_id": 10044, "object_name": "Micro-ondas", "detection_class": "microwave oven", "is_active": true, "is_ambiguous": false, "material_name": "Eletrônico", "category_name": "Eletrônico", "bin_name": "Coleta especial", "recommendation": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "preparation_instructions": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "special_waste": ["Eletrônico"], "variant_count": 0}, {"object_id": 10045, "object_name": "Geladeira", "detection_class": "refrigerator", "is_active": true, "is_ambiguous": false, "material_name": "Eletrônico", "category_name": "Eletrônico", "bin_name": "Coleta especial", "recommendation": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "preparation_instructions": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "special_waste": ["Eletrônico"], "variant_count": 0}, {"object_id": 10046, "object_name": "Máquina de lavar", "detection_class": "washing machine", "is_active": true, "is_ambiguous": false, "material_name": "Eletrônico", "category_name": "Eletrônico", "bin_name": "Coleta especial", "recommendation": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "preparation_instructions": "Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.", "special_waste": ["Eletrônico"], "variant_count": 0}, {"object_id": 10047, "object_name": "Pneu", "detection_class": "tire", "is_active": true, "is_ambiguous": false, "material_name": "Descarte especial", "category_name": "Descarte especial", "bin_name": "Coleta especial", "recommendation": "Entregue em ponto de recebimento de pneus ou revendedor participante da logística reversa.", "preparation_instructions": "Entregue em ponto de recebimento de pneus ou revendedor participante da logística reversa.", "special_waste": ["Descarte especial"], "variant_count": 0}, {"object_id": 10048, "object_name": "Roupa", "detection_class": "clothing", "is_active": true, "is_ambiguous": false, "material_name": "Descarte especial", "category_name": "Descarte especial", "bin_name": "Coleta especial", "recommendation": "Priorize doação ou reuso. Para peças inutilizadas, confirme coleta de têxteis ou calçados na sua cidade.", "preparation_instructions": "Priorize doação ou reuso. Para peças inutilizadas, confirme coleta de têxteis ou calçados na sua cidade.", "special_waste": ["Descarte especial"], "variant_count": 0}, {"object_id": 10049, "object_name": "Calçado", "detection_class": "shoe", "is_active": true, "is_ambiguous": false, "material_name": "Descarte especial", "category_name": "Descarte especial", "bin_name": "Coleta especial", "recommendation": "Priorize doação ou reuso. Para peças inutilizadas, confirme coleta de têxteis ou calçados na sua cidade.", "preparation_instructions": "Priorize doação ou reuso. Para peças inutilizadas, confirme coleta de têxteis ou calçados na sua cidade.", "special_waste": ["Descarte especial"], "variant_count": 0}, {"object_id": 10050, "object_name": "Cartela de medicamento", "detection_class": "medicine blister pack", "is_active": true, "is_ambiguous": false, "material_name": "Descarte especial", "category_name": "Descarte especial", "bin_name": "Coleta especial", "recommendation": "Se ainda houver medicamento, entregue em ponto de logística reversa de medicamentos. Embalagem vazia: confirme o destino aceito localmente.", "preparation_instructions": "Se ainda houver medicamento, entregue em ponto de logística reversa de medicamentos. Embalagem vazia: confirme o destino aceito localmente.", "special_waste": ["Descarte especial"], "variant_count": 0}, {"object_id": 10051, "object_name": "Garrafa de óleo de cozinha", "detection_class": "cooking oil bottle", "is_active": true, "is_ambiguous": false, "material_name": "Descarte especial", "category_name": "Descarte especial", "bin_name": "Coleta especial", "recommendation": "Se houver óleo usado, entregue o óleo em recipiente fechado em coleta específica. Embalagem vazia segue a coleta do seu material; a imagem não confirma o conteúdo.", "preparation_instructions": "Se houver óleo usado, entregue o óleo em recipiente fechado em coleta específica. Embalagem vazia segue a coleta do seu material; a imagem não confirma o conteúdo.", "special_waste": ["Descarte especial"], "variant_count": 0}, {"object_id": 10052, "object_name": "Restos de alimentos", "detection_class": "food waste", "is_active": true, "is_ambiguous": false, "material_name": "Orgânico", "category_name": "Orgânico", "bin_name": "Marrom", "recommendation": "Separe das embalagens para compostagem ou coleta orgânica.", "preparation_instructions": "Separe das embalagens para compostagem ou coleta orgânica.", "special_waste": [], "variant_count": 0}, {"object_id": 10053, "object_name": "Recipiente de metal", "detection_class": "metal container", "is_active": true, "is_ambiguous": false, "material_name": "Metal", "category_name": "Metal", "bin_name": "Amarela", "recommendation": "Esvazie, retire o excesso de resíduos e encaminhe para a coleta de metais aceita localmente.", "preparation_instructions": "Esvazie, retire o excesso de resíduos e encaminhe para a coleta de metais aceita localmente.", "special_waste": [], "variant_count": 0}, {"object_id": 10054, "object_name": "Embalagem plástica", "detection_class": "plastic wrapper", "is_active": true, "is_ambiguous": false, "material_name": "Plástico", "category_name": "Plástico", "bin_name": "Vermelha", "recommendation": "Esvazie, retire o excesso de resíduos e confirme o tipo de plástico aceito na coleta seletiva local.", "preparation_instructions": "Esvazie, retire o excesso de resíduos e confirme o tipo de plástico aceito na coleta seletiva local.", "special_waste": [], "variant_count": 0}, {"object_id": 10055, "object_name": "Frasco de detergente", "detection_class": "detergent bottle", "is_active": true, "is_ambiguous": false, "material_name": "Plástico", "category_name": "Plástico", "bin_name": "Vermelha", "recommendation": "Esvazie, retire o excesso de resíduos e confirme o tipo de plástico aceito na coleta seletiva local.", "preparation_instructions": "Esvazie, retire o excesso de resíduos e confirme o tipo de plástico aceito na coleta seletiva local.", "special_waste": [], "variant_count": 0}, {"object_id": 10056, "object_name": "Frasco de shampoo", "detection_class": "shampoo bottle", "is_active": true, "is_ambiguous": false, "material_name": "Plástico", "category_name": "Plástico", "bin_name": "Vermelha", "recommendation": "Esvazie, retire o excesso de resíduos e confirme o tipo de plástico aceito na coleta seletiva local.", "preparation_instructions": "Esvazie, retire o excesso de resíduos e confirme o tipo de plástico aceito na coleta seletiva local.", "special_waste": [], "variant_count": 0}]'::jsonb) on conflict(object_id) do update set object_name=excluded.object_name,detection_class=excluded.detection_class,is_active=excluded.is_active,is_ambiguous=excluded.is_ambiguous,material_name=excluded.material_name,category_name=excluded.category_name,bin_name=excluded.bin_name,recommendation=excluded.recommendation,preparation_instructions=excluded.preparation_instructions,special_waste=excluded.special_waste,variant_count=excluded.variant_count;
insert into public.object_aliases select * from jsonb_populate_recordset(null::public.object_aliases, '[{"object_id": 10000, "variant_id": null, "normalized_alias": "plastic bottle", "is_active": true}, {"object_id": 10001, "variant_id": null, "normalized_alias": "glass bottle", "is_active": true}, {"object_id": 10002, "variant_id": null, "normalized_alias": "aluminum can", "is_active": true}, {"object_id": 10003, "variant_id": null, "normalized_alias": "steel can", "is_active": true}, {"object_id": 10004, "variant_id": null, "normalized_alias": "cardboard box", "is_active": true}, {"object_id": 10005, "variant_id": null, "normalized_alias": "cardboard", "is_active": true}, {"object_id": 10006, "variant_id": null, "normalized_alias": "paper", "is_active": true}, {"object_id": 10007, "variant_id": null, "normalized_alias": "newspaper", "is_active": true}, {"object_id": 10008, "variant_id": null, "normalized_alias": "magazine", "is_active": true}, {"object_id": 10009, "variant_id": null, "normalized_alias": "book", "is_active": true}, {"object_id": 10010, "variant_id": null, "normalized_alias": "envelope", "is_active": true}, {"object_id": 10011, "variant_id": null, "normalized_alias": "plastic bag", "is_active": true}, {"object_id": 10012, "variant_id": null, "normalized_alias": "paper bag", "is_active": true}, {"object_id": 10013, "variant_id": null, "normalized_alias": "plastic cup", "is_active": true}, {"object_id": 10014, "variant_id": null, "normalized_alias": "paper cup", "is_active": true}, {"object_id": 10015, "variant_id": null, "normalized_alias": "glass jar", "is_active": true}, {"object_id": 10016, "variant_id": null, "normalized_alias": "plastic container", "is_active": true}, {"object_id": 10017, "variant_id": null, "normalized_alias": "food container", "is_active": true}, {"object_id": 10018, "variant_id": null, "normalized_alias": "beverage carton", "is_active": true}, {"object_id": 10019, "variant_id": null, "normalized_alias": "aerosol can", "is_active": true}, {"object_id": 10020, "variant_id": null, "normalized_alias": "battery", "is_active": true}, {"object_id": 10021, "variant_id": null, "normalized_alias": "car battery", "is_active": true}, {"object_id": 10022, "variant_id": null, "normalized_alias": "light bulb", "is_active": true}, {"object_id": 10023, "variant_id": null, "normalized_alias": "fluorescent lamp", "is_active": true}, {"object_id": 10024, "variant_id": null, "normalized_alias": "smartphone", "is_active": true}, {"object_id": 10025, "variant_id": null, "normalized_alias": "tablet", "is_active": true}, {"object_id": 10026, "variant_id": null, "normalized_alias": "laptop", "is_active": true}, {"object_id": 10027, "variant_id": null, "normalized_alias": "computer monitor", "is_active": true}, {"object_id": 10028, "variant_id": null, "normalized_alias": "computer keyboard", "is_active": true}, {"object_id": 10029, "variant_id": null, "normalized_alias": "computer mouse", "is_active": true}, {"object_id": 10030, "variant_id": null, "normalized_alias": "printer", "is_active": true}, {"object_id": 10031, "variant_id": null, "normalized_alias": "television", "is_active": true}, {"object_id": 10032, "variant_id": null, "normalized_alias": "phone charger", "is_active": true}, {"object_id": 10033, "variant_id": null, "normalized_alias": "power cable", "is_active": true}, {"object_id": 10034, "variant_id": null, "normalized_alias": "headphones", "is_active": true}, {"object_id": 10035, "variant_id": null, "normalized_alias": "earphones", "is_active": true}, {"object_id": 10036, "variant_id": null, "normalized_alias": "circuit board", "is_active": true}, {"object_id": 10037, "variant_id": null, "normalized_alias": "router", "is_active": true}, {"object_id": 10038, "variant_id": null, "normalized_alias": "power bank", "is_active": true}, {"object_id": 10039, "variant_id": null, "normalized_alias": "electronic device", "is_active": true}, {"object_id": 10040, "variant_id": null, "normalized_alias": "camera", "is_active": true}, {"object_id": 10041, "variant_id": null, "normalized_alias": "speaker", "is_active": true}, {"object_id": 10042, "variant_id": null, "normalized_alias": "game controller", "is_active": true}, {"object_id": 10043, "variant_id": null, "normalized_alias": "remote control", "is_active": true}, {"object_id": 10044, "variant_id": null, "normalized_alias": "microwave oven", "is_active": true}, {"object_id": 10045, "variant_id": null, "normalized_alias": "refrigerator", "is_active": true}, {"object_id": 10046, "variant_id": null, "normalized_alias": "washing machine", "is_active": true}, {"object_id": 10047, "variant_id": null, "normalized_alias": "tire", "is_active": true}, {"object_id": 10048, "variant_id": null, "normalized_alias": "clothing", "is_active": true}, {"object_id": 10049, "variant_id": null, "normalized_alias": "shoe", "is_active": true}, {"object_id": 10050, "variant_id": null, "normalized_alias": "medicine blister pack", "is_active": true}, {"object_id": 10051, "variant_id": null, "normalized_alias": "cooking oil bottle", "is_active": true}, {"object_id": 10052, "variant_id": null, "normalized_alias": "food waste", "is_active": true}, {"object_id": 10053, "variant_id": null, "normalized_alias": "metal container", "is_active": true}, {"object_id": 10054, "variant_id": null, "normalized_alias": "plastic wrapper", "is_active": true}, {"object_id": 10055, "variant_id": null, "normalized_alias": "detergent bottle", "is_active": true}, {"object_id": 10056, "variant_id": null, "normalized_alias": "shampoo bottle", "is_active": true}]'::jsonb) on conflict(object_id,variant_id,normalized_alias) do update set is_active=excluded.is_active;
-- <<< MIGRATION 202609300001_yoloe_catalog.sql

-- >>> MIGRATION 202610020001_fato_scan.sql
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
-- <<< MIGRATION 202610020001_fato_scan.sql

-- >>> MIGRATION 202610080001_learning_reports.sql
-- Prepares the private image bucket and correction table used by EcoScan.
create table if not exists public.ecoscan_training_samples (
  user_id uuid not null references auth.users(id) on delete cascade,
  client_sample_id text not null,
  storage_path text not null,
  source text not null,
  detector text not null,
  detections jsonb not null default '[]'::jsonb,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected', 'trained')),
  verified_label text,
  verified_bin text,
  annotations jsonb not null default '[]'::jsonb,
  user_reported_label text,
  user_reported_bin text,
  report_note text,
  ai_detected boolean,
  original_label text,
  original_confidence double precision check (
    original_confidence is null or original_confidence between 0 and 1
  ),
  consented_at timestamptz not null default now(),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (user_id, client_sample_id)
);

alter table public.ecoscan_training_samples
  add column if not exists verified_bin text,
  add column if not exists user_reported_label text,
  add column if not exists user_reported_bin text,
  add column if not exists report_note text,
  add column if not exists ai_detected boolean,
  add column if not exists original_label text,
  add column if not exists original_confidence double precision;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'ecoscan_training_samples_original_confidence_check'
      and conrelid = 'public.ecoscan_training_samples'::regclass
  ) then
    alter table public.ecoscan_training_samples
      add constraint ecoscan_training_samples_original_confidence_check
      check (original_confidence is null or original_confidence between 0 and 1);
  end if;
end;
$$;

alter table public.ecoscan_training_samples enable row level security;
grant select, insert, update on public.ecoscan_training_samples to authenticated;

drop policy if exists "users read their EcoScan training samples"
  on public.ecoscan_training_samples;
create policy "users read their EcoScan training samples"
on public.ecoscan_training_samples
for select to authenticated
using (auth.uid() = user_id);

drop policy if exists "users create their EcoScan training samples"
  on public.ecoscan_training_samples;
create policy "users create their EcoScan training samples"
on public.ecoscan_training_samples
for insert to authenticated
with check (
  auth.uid() = user_id
  and status = 'pending'
  and verified_label is null
  and annotations = '[]'::jsonb
);

drop policy if exists "users retry pending EcoScan training samples"
  on public.ecoscan_training_samples;
create policy "users retry pending EcoScan training samples"
on public.ecoscan_training_samples
for update to authenticated
using (auth.uid() = user_id and status = 'pending')
with check (
  auth.uid() = user_id
  and status = 'pending'
  and verified_label is null
  and annotations = '[]'::jsonb
);

insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
) values (
  'ecoscan-training', 'ecoscan-training', false, 10485760, array['image/jpeg']
)
on conflict (id) do update set
  name = excluded.name,
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "users upload their own EcoScan training images"
  on storage.objects;
create policy "users upload their own EcoScan training images"
on storage.objects
for insert to authenticated
with check (
  bucket_id = 'ecoscan-training'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "users replace their own pending training images"
  on storage.objects;
create policy "users replace their own pending training images"
on storage.objects
for update to authenticated
using (
  bucket_id = 'ecoscan-training'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'ecoscan-training'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "users read their own EcoScan training images"
  on storage.objects;
create policy "users read their own EcoScan training images"
on storage.objects
for select to authenticated
using (
  bucket_id = 'ecoscan-training'
  and (storage.foldername(name))[1] = auth.uid()::text
);
-- <<< MIGRATION 202610080001_learning_reports.sql

-- >>> MIGRATION 202610150001_automatic_database.sql
-- EcoScan 3.4.9: first automatic account-data sync and safe catalog resolution.
-- Run after 202610080001_learning_reports.sql.
alter table public.fato_scan
  add column if not exists object_id bigint
    references public.objects(object_id) on delete set null,
  add column if not exists variant_id bigint
    references public.object_variants(variant_id) on delete set null,
  add column if not exists detection_label text,
  add column if not exists class_index integer,
  add column if not exists confirmed_by_user boolean not null default false;

create index if not exists fato_scan_object_id_idx
  on public.fato_scan(object_id) where object_id is not null;

grant delete on public.fato_scan to authenticated;
drop policy if exists fato_scan_own_delete on public.fato_scan;
create policy fato_scan_own_delete
on public.fato_scan
for delete to authenticated
using ((select auth.uid()) = user_id);

create unique index if not exists object_variants_object_variant_unique
  on public.object_variants(object_id, variant_id);

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'fato_scan_variant_matches_object_fk'
      and conrelid = 'public.fato_scan'::regclass
  ) then
    alter table public.fato_scan
      add constraint fato_scan_variant_matches_object_fk
      foreign key (object_id, variant_id)
      references public.object_variants(object_id, variant_id);
  end if;
end;
$$;

create or replace function public.find_ecoscan_object(p_alias text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
with normalized_input as (
  select public.ecoscan_normalize_alias(p_alias) as value
), matches as (
  select distinct
    o.object_id,
    v.variant_id,
    case
      when a.normalized_alias = n.value then 1
      when public.ecoscan_normalize_alias(o.object_name) = n.value then 2
      else 3
    end as match_priority,
    to_jsonb(o) || jsonb_build_object(
      'variant_id', v.variant_id,
      'material_name', coalesce(v.material_name, o.material_name),
      'category_name', coalesce(v.category_name, o.category_name),
      'bin_name', coalesce(v.bin_name, o.bin_name),
      'recommendation', coalesce(v.recommendation, o.recommendation),
      'preparation_instructions', coalesce(
        v.preparation_instructions, o.preparation_instructions
      )
    ) as payload
  from public.objects o
  cross join normalized_input n
  left join public.object_aliases a
    on a.object_id = o.object_id
   and a.is_active
   and a.normalized_alias = n.value
  left join public.object_variants v on v.variant_id = a.variant_id
  where o.is_active
    and n.value <> ''
    and (
      (a.normalized_alias = n.value and (not o.is_ambiguous or v.variant_id is not null))
      or (not o.is_ambiguous and public.ecoscan_normalize_alias(o.object_name) = n.value)
      or (not o.is_ambiguous and public.ecoscan_normalize_alias(o.detection_class) = n.value)
    )
), best_matches as (
  select payload
  from matches
  where match_priority = (select min(match_priority) from matches)
)
select case
  when count(*) = 1 then jsonb_agg(payload)->0
  else null
end
from best_matches;
$$;

revoke all on function public.find_ecoscan_object(text) from public;
grant execute on function public.find_ecoscan_object(text) to anon, authenticated;

-- Tombstones prevent a deleted scan on one device from being resurrected by
-- an offline copy on another device.
create table if not exists public.fato_scan_deletions (
  user_id uuid not null references auth.users(id) on delete cascade,
  client_scan_id text not null,
  deleted_at timestamptz not null default now(),
  primary key (user_id, client_scan_id)
);

alter table public.fato_scan_deletions enable row level security;
grant select, insert, update on public.fato_scan_deletions to authenticated;

drop policy if exists fato_scan_deletions_own_read
  on public.fato_scan_deletions;
create policy fato_scan_deletions_own_read
on public.fato_scan_deletions
for select to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists fato_scan_deletions_own_insert
  on public.fato_scan_deletions;
create policy fato_scan_deletions_own_insert
on public.fato_scan_deletions
for insert to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists fato_scan_deletions_own_update
  on public.fato_scan_deletions;
create policy fato_scan_deletions_own_update
on public.fato_scan_deletions
for update to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create or replace view public.ecoscan_user_history
with (security_invoker = true)
as
select scan.*
from public.fato_scan scan
where not exists (
  select 1
  from public.fato_scan_deletions deleted
  where deleted.user_id = scan.user_id
    and deleted.client_scan_id = scan.client_scan_id
);

grant select on public.ecoscan_user_history to authenticated;

-- RLS on fato_scan limits this view to the caller's own rows.
create or replace view public.ecoscan_user_stats
with (security_invoker = true)
as
select
  user_id,
  count(*)::bigint as scan_count,
  count(*) filter (where confirmed_by_user)::bigint as confirmed_scan_count,
  count(distinct nullif(category_name, ''))::bigint as material_count,
  (
    count(*) * 10
    + count(*) filter (where category_name in ('Papel', 'Plástico', 'Vidro', 'Metal')) * 5
    + count(distinct nullif(category_name, '')) * 10
    + count(*) filter (
        where category_name in ('Papel', 'Plástico', 'Vidro', 'Metal', 'Orgânico', 'Eletrônico')
      ) * 5
  )::bigint as eco_points,
  min(detected_at) as first_scan_at,
  max(detected_at) as last_scan_at
from public.ecoscan_user_history
group by user_id;

grant select on public.ecoscan_user_stats to authenticated;

notify pgrst, 'reload schema';
-- <<< MIGRATION 202610150001_automatic_database.sql

-- >>> MIGRATION 202610160001_schema_ptbr.sql
-- Migra o esquema inicial para nomes em português e completa o modelo relacional.
-- auth.users e storage.* são esquemas internos do Supabase e permanecem intactos.
drop view if exists public.ecoscan_user_stats;
drop view if exists public.ecoscan_user_history;

do $$
declare
  item record;
begin
  for item in
    select * from (values
      ('profiles','perfis'),
      ('ecopoints','pontos_ecologicos'),
      ('objects','objetos'),
      ('object_variants','variantes_objeto'),
      ('object_aliases','sinonimos_objeto'),
      ('ecoscan_model_releases','versoes_modelo'),
      ('ecoscan_training_samples','amostras_treinamento'),
      ('fato_scan','leituras_scan'),
      ('fato_scan_deletions','exclusoes_leitura')
    ) as nomes(antigo, novo)
  loop
    if to_regclass('public.' || item.antigo) is not null
       and to_regclass('public.' || item.novo) is null then
      execute format('alter table public.%I rename to %I', item.antigo, item.novo);
    end if;
  end loop;

  for item in
    select * from (values
      ('perfis','id','usuario_id'),
      ('perfis','full_name','nome_completo'),
      ('perfis','created_at','criado_em'),
      ('perfis','updated_at','atualizado_em'),
      ('pontos_ecologicos','id','ponto_id'),
      ('pontos_ecologicos','name','nome'),
      ('pontos_ecologicos','type','tipo'),
      ('pontos_ecologicos','category','categoria'),
      ('pontos_ecologicos','location','localizacao_geografica'),
      ('pontos_ecologicos','address','endereco'),
      ('pontos_ecologicos','opening_hours','horario_atendimento'),
      ('pontos_ecologicos','accepted_material_ids','materiais_aceitos_ids'),
      ('pontos_ecologicos','accepted_materials_description','descricao_materiais_aceitos'),
      ('pontos_ecologicos','district','distrito'),
      ('pontos_ecologicos','administrative_area','subprefeitura'),
      ('pontos_ecologicos','source','fonte'),
      ('pontos_ecologicos','source_url','url_fonte'),
      ('pontos_ecologicos','is_active','ativo'),
      ('pontos_ecologicos','updated_at','atualizado_em'),
      ('objetos','object_id','objeto_id'),
      ('objetos','object_name','nome'),
      ('objetos','detection_class','classe_deteccao'),
      ('objetos','is_active','ativo'),
      ('objetos','is_ambiguous','ambiguo'),
      ('objetos','material_name','nome_material'),
      ('objetos','category_name','categoria'),
      ('objetos','bin_name','cor_lixeira'),
      ('objetos','recommendation','recomendacao'),
      ('objetos','preparation_instructions','instrucoes_preparo'),
      ('objetos','special_waste','residuos_especiais'),
      ('objetos','variant_count','quantidade_variantes'),
      ('variantes_objeto','variant_id','variante_id'),
      ('variantes_objeto','object_id','objeto_id'),
      ('variantes_objeto','material_name','nome_material'),
      ('variantes_objeto','category_name','categoria'),
      ('variantes_objeto','bin_name','cor_lixeira'),
      ('variantes_objeto','recommendation','recomendacao'),
      ('variantes_objeto','preparation_instructions','instrucoes_preparo'),
      ('sinonimos_objeto','object_id','objeto_id'),
      ('sinonimos_objeto','variant_id','variante_id'),
      ('sinonimos_objeto','normalized_alias','sinonimo_normalizado'),
      ('sinonimos_objeto','is_active','ativo'),
      ('versoes_modelo','id','versao_id'),
      ('versoes_modelo','platform','plataforma'),
      ('versoes_modelo','version','versao'),
      ('versoes_modelo','bucket_id','id_bucket'),
      ('versoes_modelo','object_path','caminho_arquivo'),
      ('versoes_modelo','sha256','hash_sha256'),
      ('versoes_modelo','byte_size','tamanho_bytes'),
      ('versoes_modelo','is_active','ativa'),
      ('versoes_modelo','notes','observacoes'),
      ('versoes_modelo','created_at','criado_em'),
      ('amostras_treinamento','user_id','usuario_id'),
      ('amostras_treinamento','client_sample_id','id_amostra_cliente'),
      ('amostras_treinamento','storage_path','caminho_arquivo'),
      ('amostras_treinamento','source','origem'),
      ('amostras_treinamento','detector','mecanismo_deteccao'),
      ('amostras_treinamento','detections','deteccoes'),
      ('amostras_treinamento','status','situacao'),
      ('amostras_treinamento','verified_label','rotulo_confirmado'),
      ('amostras_treinamento','verified_bin','lixeira_confirmada'),
      ('amostras_treinamento','annotations','anotacoes'),
      ('amostras_treinamento','user_reported_label','rotulo_informado_usuario'),
      ('amostras_treinamento','user_reported_bin','lixeira_informada_usuario'),
      ('amostras_treinamento','report_note','observacao'),
      ('amostras_treinamento','ai_detected','detectado_por_ia'),
      ('amostras_treinamento','original_label','rotulo_original'),
      ('amostras_treinamento','original_confidence','confianca_original'),
      ('amostras_treinamento','consented_at','consentido_em'),
      ('amostras_treinamento','reviewed_at','revisado_em'),
      ('amostras_treinamento','created_at','criado_em'),
      ('leituras_scan','user_id','usuario_id'),
      ('leituras_scan','client_scan_id','id_leitura_cliente'),
      ('leituras_scan','object_name','nome_objeto'),
      ('leituras_scan','material_name','nome_material'),
      ('leituras_scan','category_name','categoria'),
      ('leituras_scan','bin_name','cor_lixeira'),
      ('leituras_scan','destination','destino'),
      ('leituras_scan','confidence','confianca'),
      ('leituras_scan','source','origem'),
      ('leituras_scan','detector','mecanismo_deteccao'),
      ('leituras_scan','detected_at','analisado_em'),
      ('leituras_scan','created_at','criado_em'),
      ('leituras_scan','object_id','objeto_id'),
      ('leituras_scan','variant_id','variante_id'),
      ('leituras_scan','detection_label','rotulo_detectado'),
      ('leituras_scan','class_index','indice_classe'),
      ('leituras_scan','confirmed_by_user','confirmado_pelo_usuario'),
      ('exclusoes_leitura','user_id','usuario_id'),
      ('exclusoes_leitura','client_scan_id','id_leitura_cliente'),
      ('exclusoes_leitura','deleted_at','excluido_em')
    ) as colunas(tabela, antigo, novo)
  loop
    if to_regclass('public.' || item.tabela) is not null
       and exists (
         select 1 from information_schema.columns
         where table_schema = 'public' and table_name = item.tabela
           and column_name = item.antigo
       )
       and not exists (
         select 1 from information_schema.columns
         where table_schema = 'public' and table_name = item.tabela
           and column_name = item.novo
       ) then
      execute format(
        'alter table public.%I rename column %I to %I',
        item.tabela, item.antigo, item.novo
      );
    end if;
  end loop;
end;
$$;

alter table public.pontos_ecologicos alter column categoria set default 'reciclagem';
alter table public.pontos_ecologicos drop constraint if exists ecopoints_category_check;
update public.pontos_ecologicos set categoria = case categoria
  when 'recycling' then 'reciclagem'
  when 'disposal' then 'descarte'
  else categoria
end;
alter table public.pontos_ecologicos add constraint pontos_ecologicos_categoria_check
  check (categoria in ('reciclagem','descarte'));

drop trigger if exists ecoscan_profile on auth.users;
drop trigger if exists sincronizar_perfis_auth on auth.users;
drop function if exists public.ecoscan_sync_profile();
create or replace function public.sincronizar_perfil_ecoscan()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.perfis(usuario_id, email, nome_completo, atualizado_em)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', ''),
    now()
  )
  on conflict(usuario_id) do update set
    email = excluded.email,
    nome_completo = excluded.nome_completo,
    atualizado_em = now();
  return new;
end;
$$;
revoke all on function public.sincronizar_perfil_ecoscan() from public, anon, authenticated;
drop trigger if exists ecoscan_profile on auth.users;
drop trigger if exists sincronizar_perfis_auth on auth.users;
create trigger sincronizar_perfis_auth after insert or update of email, raw_user_meta_data on auth.users
for each row execute function public.sincronizar_perfil_ecoscan();

create or replace function public.normalizar_texto_ecoscan(p_texto text)
returns text language sql stable set search_path = '' as $$
  select trim(regexp_replace(lower(extensions.unaccent(coalesce(p_texto, ''))), '[^a-z0-9]+', ' ', 'g'));
$$;

create or replace function public.gerar_id_material_ecoscan(p_nome text)
returns text language sql stable set search_path = '' as $$
  select nullif(regexp_replace(public.normalizar_texto_ecoscan(p_nome), ' +', '_', 'g'), '');
$$;

create or replace function public.resolver_id_material_ecoscan(p_nome text, p_categoria text)
returns text language sql stable set search_path = '' as $$
  with valores as (
    select public.normalizar_texto_ecoscan(coalesce(nullif(p_categoria,''), p_nome, '')) as categoria,
           public.normalizar_texto_ecoscan(coalesce(nullif(p_nome,''), p_categoria, '')) as nome
  )
  select case
    when nome in ('papelao','papeloes') then 'papelao'
    when categoria in ('plastico','plasticos') or nome in ('plastico','plasticos') then 'plastico'
    when categoria in ('papel','papeis') or nome in ('papel','papeis') then 'papel'
    when categoria in ('vidro','vidros') or nome in ('vidro','vidros') then 'vidro'
    when categoria in ('metal','metais','aco') or nome in ('metal','metais','aco') then 'metal'
    when categoria in ('organico','residuos organicos','residuos alimentares')
      or nome in ('organico','residuos organicos','residuos alimentares') then 'organico'
    when categoria in ('eletronico','eletronicos') or nome in ('eletronico','eletronicos') then 'eletronico'
    when categoria in ('pilhas e baterias','pilhas baterias','baterias')
      or nome in ('pilhas e baterias','pilhas baterias','baterias') then 'pilhas_baterias'
    when categoria in ('rejeito','rejeitos') or nome in ('rejeito','rejeitos') then 'rejeito'
    when categoria in ('especial','descarte especial') or nome in ('especial','descarte especial') then 'especial'
    else 'catalogo_' || public.gerar_id_material_ecoscan(coalesce(nullif(p_nome,''), nullif(p_categoria,'')))
  end
  from valores;
$$;

create table if not exists public.materiais (
  material_id text primary key,
  nome text not null,
  categoria text,
  cor_lixeira text,
  reciclavel boolean not null default false,
  orientacao text,
  ativo boolean not null default true,
  atualizado_em timestamptz not null default now()
);

insert into public.materiais(material_id, nome, categoria, cor_lixeira, reciclavel)
values
  ('plastico','Plástico','Plástico','Vermelha',true),
  ('papel','Papel','Papel','Azul',true),
  ('vidro','Vidro','Vidro','Verde',true),
  ('metal','Metal','Metal','Amarela',true),
  ('papelao','Papelão','Papel','Azul',true),
  ('organico','Orgânico','Orgânico','Marrom',false),
  ('rejeito','Rejeito','Rejeito','Cinza',false),
  ('eletronico','Eletrônico','Descarte especial','Coleta especial',false),
  ('especial','Descarte especial','Descarte especial','Coleta especial',false),
  ('pilhas_baterias','Pilhas e baterias','Descarte especial','Coleta especial',false)
on conflict(material_id) do update set
  nome = excluded.nome,
  categoria = excluded.categoria,
  cor_lixeira = excluded.cor_lixeira,
  reciclavel = excluded.reciclavel,
  atualizado_em = now();

insert into public.materiais(material_id, nome, categoria, cor_lixeira, reciclavel, orientacao)
select distinct
  public.resolver_id_material_ecoscan(v.nome_material, v.categoria),
  coalesce(nullif(v.nome_material,''), nullif(v.categoria,'')),
  nullif(v.categoria,''),
  nullif(v.cor_lixeira,''),
  public.resolver_id_material_ecoscan(v.nome_material, v.categoria)
    in ('papel','papelao','plastico','vidro','metal'),
  nullif(coalesce(v.instrucoes_preparo, v.recomendacao), '')
from (
  select nome_material, categoria, cor_lixeira, instrucoes_preparo, recomendacao from public.objetos
  union all
  select nome_material, categoria, cor_lixeira, instrucoes_preparo, recomendacao from public.variantes_objeto
) v
where coalesce(nullif(v.nome_material,''), nullif(v.categoria,'')) is not null
on conflict(material_id) do nothing;

alter table public.objetos add column if not exists material_id text references public.materiais(material_id) on delete set null;
alter table public.variantes_objeto add column if not exists material_id text references public.materiais(material_id) on delete set null;
alter table public.leituras_scan add column if not exists material_id text references public.materiais(material_id) on delete set null;

update public.objetos o set material_id = m.material_id
from public.materiais m
where o.material_id is null
  and m.material_id = public.resolver_id_material_ecoscan(o.nome_material, o.categoria);
update public.variantes_objeto v set material_id = m.material_id
from public.materiais m
where v.material_id is null
  and m.material_id = public.resolver_id_material_ecoscan(v.nome_material, v.categoria);
update public.leituras_scan s set material_id = m.material_id
from public.materiais m
where s.material_id is null
  and m.material_id = public.resolver_id_material_ecoscan(s.nome_material, s.categoria)
  and m.ativo;

create table if not exists public.materiais_ponto_ecologico (
  ponto_id text not null references public.pontos_ecologicos(ponto_id) on delete cascade,
  material_id text not null references public.materiais(material_id) on delete restrict,
  observacao_aceite text,
  primary key (ponto_id, material_id)
);

insert into public.materiais_ponto_ecologico(ponto_id, material_id)
select distinct p.ponto_id, m.material_id
from public.pontos_ecologicos p
cross join lateral unnest(coalesce(p.materiais_aceitos_ids, '{}'::text[])) aceito(id)
join public.materiais m on m.material_id = case aceito.id
  when 'plastic' then 'plastico'
  when 'glass' then 'vidro'
  when 'paper' then 'papel'
  when 'metal' then 'metal'
  when 'cardboard' then 'papelao'
  when 'special' then 'especial'
  when 'electronic' then 'eletronico'
  when 'battery' then 'pilhas_baterias'
  when 'organic' then 'organico'
  else null
end
on conflict do nothing;

alter table public.pontos_ecologicos drop column if exists materiais_aceitos_ids;

create table if not exists public.classes_yoloe (
  classe_id bigint generated by default as identity primary key,
  versao_modelo_id bigint references public.versoes_modelo(versao_id) on delete set null,
  indice_classe integer not null check (indice_classe >= 0),
  nome_classe text not null,
  prompt text not null,
  objeto_id bigint references public.objetos(objeto_id) on delete set null,
  ativa boolean not null default true,
  criado_em timestamptz not null default now()
);
create unique index if not exists classes_yoloe_versao_indice_unico
  on public.classes_yoloe(versao_modelo_id, indice_classe)
  where versao_modelo_id is not null;
insert into public.classes_yoloe(versao_modelo_id, indice_classe, nome_classe, prompt, objeto_id)
select null, (o.objeto_id - 10000)::integer, o.classe_deteccao, o.nome, o.objeto_id
from public.objetos o
where o.objeto_id >= 10000 and o.classe_deteccao is not null
  and not exists (select 1 from public.classes_yoloe c where c.objeto_id = o.objeto_id);

create table if not exists public.configuracoes_usuario (
  usuario_id uuid primary key references auth.users(id) on delete cascade,
  tema text not null default 'escuro' check (tema in ('claro','escuro','sistema')),
  sons_ativos boolean not null default true,
  avisos_ativos boolean not null default true,
  mapa_explorado boolean not null default false,
  caminho_foto_perfil text,
  atualizado_em timestamptz not null default now()
);

create table if not exists public.conquistas (
  conquista_id text primary key,
  titulo text not null,
  descricao text not null,
  icone text not null,
  metrica text not null check (metrica in ('leituras','categorias','mapa_explorado')),
  meta integer not null check (meta > 0),
  recompensa_pontos integer not null default 0 check (recompensa_pontos >= 0),
  ativa boolean not null default true
);
insert into public.conquistas(conquista_id,titulo,descricao,icone,metrica,meta,recompensa_pontos)
values
  ('primeiro_scan','Primeiro Scan','Salve sua primeira leitura.','🌱','leituras',1,60),
  ('reciclador','Reciclador','Salve 10 leituras.','♻️','leituras',10,0),
  ('guardiao_ambiental','Guardião Ambiental','Salve 25 leituras.','🌎','leituras',25,0),
  ('mestre_sustentavel','Mestre Sustentável','Salve 50 leituras.','🏆','leituras',50,0),
  ('explorador_verde','Explorador Verde','Explore o mapa de EcoPontos.','📍','mapa_explorado',1,0),
  ('educador_verde','Educador Verde','Salve 100 leituras.','📚','leituras',100,0),
  ('detetive_materiais','Detetive dos Materiais','Identifique 5 categorias.','🧠','categorias',5,0),
  ('destino_correto','Destino Certo','Salve 10 leituras.','🗑️','leituras',10,0)
on conflict(conquista_id) do update set
  titulo=excluded.titulo, descricao=excluded.descricao, icone=excluded.icone,
  metrica=excluded.metrica, meta=excluded.meta,
  recompensa_pontos=excluded.recompensa_pontos, ativa=true;

create table if not exists public.eventos_pontos (
  evento_id bigint generated by default as identity primary key,
  usuario_id uuid not null references auth.users(id) on delete cascade,
  id_leitura_cliente text,
  tipo_evento text not null,
  chave_idempotencia text not null,
  pontos integer not null,
  categoria text,
  criado_em timestamptz not null default now(),
  unique(usuario_id, chave_idempotencia)
);
alter table public.eventos_pontos
  add constraint eventos_pontos_leitura_fk
  foreign key (usuario_id, id_leitura_cliente)
  references public.leituras_scan(usuario_id, id_leitura_cliente)
  on delete cascade;
create index if not exists eventos_pontos_usuario_data_idx
  on public.eventos_pontos(usuario_id, criado_em desc);

create table if not exists public.conquistas_usuario (
  usuario_id uuid not null references auth.users(id) on delete cascade,
  conquista_id text not null references public.conquistas(conquista_id) on delete cascade,
  progresso integer not null default 0 check (progresso >= 0),
  desbloqueada_em timestamptz,
  atualizado_em timestamptz not null default now(),
  primary key(usuario_id, conquista_id)
);

alter table public.amostras_treinamento drop constraint if exists ecoscan_training_samples_status_check;
update public.amostras_treinamento
set situacao = case situacao
  when 'pending' then 'pendente'
  when 'approved' then 'aprovada'
  when 'rejected' then 'rejeitada'
  when 'trained' then 'treinada'
  else situacao
end;
alter table public.amostras_treinamento add constraint amostras_treinamento_situacao_check
  check (situacao in ('pendente','aprovada','rejeitada','treinada'));
alter table public.amostras_treinamento add column if not exists id_leitura_cliente text;
alter table public.amostras_treinamento
  add constraint amostras_leitura_origem_fk
  foreign key (usuario_id, id_leitura_cliente)
  references public.leituras_scan(usuario_id, id_leitura_cliente)
  on delete set null (id_leitura_cliente);

-- As visões usam o usuário que consulta e herdam as regras de acesso das tabelas.
create or replace view public.historico_leituras_usuario
with (security_invoker = true)
as
select leitura.*
from public.leituras_scan leitura
where not exists (
  select 1 from public.exclusoes_leitura exclusao
  where exclusao.usuario_id = leitura.usuario_id
    and exclusao.id_leitura_cliente = leitura.id_leitura_cliente
);
grant select on public.historico_leituras_usuario to authenticated;

create or replace function public.recalcular_dados_usuario_ecoscan(p_usuario_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  quantidade_leituras integer;
  quantidade_categorias integer;
  mapa_visitado boolean;
begin
  if p_usuario_id is null then return; end if;

  perform pg_advisory_xact_lock(hashtextextended(p_usuario_id::text, 0));

  delete from public.eventos_pontos where usuario_id = p_usuario_id;

  insert into public.eventos_pontos(
    usuario_id, id_leitura_cliente, tipo_evento, chave_idempotencia, pontos, categoria
  )
  select s.usuario_id, s.id_leitura_cliente, 'leitura_salva',
         'leitura:' || s.id_leitura_cliente, 10, s.categoria
  from public.historico_leituras_usuario s where s.usuario_id = p_usuario_id
  union all
  select s.usuario_id, s.id_leitura_cliente, 'material_reciclavel',
         'reciclagem:' || s.id_leitura_cliente, 5, s.categoria
  from public.historico_leituras_usuario s
  where s.usuario_id = p_usuario_id and s.categoria in ('Papel','Plástico','Vidro','Metal')
  union all
  select s.usuario_id, s.id_leitura_cliente, 'categoria_pontuavel',
         'categoria_pontuavel:' || s.id_leitura_cliente, 5, s.categoria
  from public.historico_leituras_usuario s
  where s.usuario_id = p_usuario_id
    and s.categoria in ('Papel','Plástico','Vidro','Metal','Orgânico','Eletrônico')
  union all
  select primeira.usuario_id, primeira.id_leitura_cliente, 'nova_categoria',
         'categoria:' || lower(primeira.categoria), 10, primeira.categoria
  from (
    select distinct on (s.categoria) s.usuario_id, s.id_leitura_cliente, s.categoria
    from public.historico_leituras_usuario s
    where s.usuario_id = p_usuario_id and nullif(s.categoria,'') is not null
    order by s.categoria, s.analisado_em, s.id_leitura_cliente
  ) primeira;

  select count(*)::integer,
         count(distinct nullif(categoria,''))::integer
  into quantidade_leituras, quantidade_categorias
  from public.historico_leituras_usuario where usuario_id = p_usuario_id;

  select coalesce(mapa_explorado,false) into mapa_visitado
  from public.configuracoes_usuario where usuario_id = p_usuario_id;
  mapa_visitado := coalesce(mapa_visitado,false);

  insert into public.conquistas_usuario(usuario_id, conquista_id, progresso, desbloqueada_em, atualizado_em)
  select p_usuario_id, c.conquista_id,
    case c.metrica
      when 'leituras' then quantidade_leituras
      when 'categorias' then quantidade_categorias
      when 'mapa_explorado' then case when mapa_visitado then 1 else 0 end
    end,
    case when case c.metrica
      when 'leituras' then quantidade_leituras
      when 'categorias' then quantidade_categorias
      when 'mapa_explorado' then case when mapa_visitado then 1 else 0 end
    end >= c.meta then now() else null end,
    now()
  from public.conquistas c where c.ativa
  on conflict(usuario_id, conquista_id) do update set
    progresso = excluded.progresso,
    desbloqueada_em = coalesce(public.conquistas_usuario.desbloqueada_em, excluded.desbloqueada_em),
    atualizado_em = now();

  insert into public.eventos_pontos(
    usuario_id, tipo_evento, chave_idempotencia, pontos
  )
  select p_usuario_id, 'conquista_desbloqueada', 'conquista:' || c.conquista_id,
         c.recompensa_pontos
  from public.conquistas_usuario uc
  join public.conquistas c on c.conquista_id=uc.conquista_id
  where uc.usuario_id=p_usuario_id
    and uc.desbloqueada_em is not null
    and c.ativa
    and c.recompensa_pontos > 0
  on conflict(usuario_id, chave_idempotencia) do nothing;
end;
$$;
revoke all on function public.recalcular_dados_usuario_ecoscan(uuid) from public, anon, authenticated;

create or replace function public.ao_alterar_leitura_ecoscan()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    perform public.recalcular_dados_usuario_ecoscan(old.usuario_id);
    return old;
  end if;
  perform public.recalcular_dados_usuario_ecoscan(new.usuario_id);
  return new;
end;
$$;
revoke all on function public.ao_alterar_leitura_ecoscan() from public, anon, authenticated;
drop trigger if exists leitura_recalcular_dados on public.leituras_scan;
create trigger leitura_recalcular_dados after insert or update or delete on public.leituras_scan
for each row execute function public.ao_alterar_leitura_ecoscan();

create or replace function public.ao_alterar_exclusao_ecoscan()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    perform public.recalcular_dados_usuario_ecoscan(old.usuario_id);
    return old;
  end if;
  perform public.recalcular_dados_usuario_ecoscan(new.usuario_id);
  return new;
end;
$$;
revoke all on function public.ao_alterar_exclusao_ecoscan() from public, anon, authenticated;
drop trigger if exists exclusao_recalcular_dados on public.exclusoes_leitura;
create trigger exclusao_recalcular_dados after insert or update or delete on public.exclusoes_leitura
for each row execute function public.ao_alterar_exclusao_ecoscan();

create or replace function public.ao_alterar_configuracao_ecoscan()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    if new.mapa_explorado then
      perform public.recalcular_dados_usuario_ecoscan(new.usuario_id);
    end if;
  elsif old.mapa_explorado is distinct from new.mapa_explorado then
    perform public.recalcular_dados_usuario_ecoscan(new.usuario_id);
  end if;
  return new;
end;
$$;
revoke all on function public.ao_alterar_configuracao_ecoscan() from public, anon, authenticated;
drop trigger if exists configuracao_recalcular_conquistas on public.configuracoes_usuario;
create trigger configuracao_recalcular_conquistas after insert or update on public.configuracoes_usuario
for each row execute function public.ao_alterar_configuracao_ecoscan();

-- Reconstrói o perfil e as conquistas de contas já existentes nesta base.
insert into public.perfis(usuario_id, email, nome_completo, atualizado_em)
select u.id, u.email,
       coalesce(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name', ''),
       now()
from auth.users u
on conflict(usuario_id) do update set
  email=excluded.email,
  nome_completo=excluded.nome_completo,
  atualizado_em=now();

do $$
declare usuario record;
begin
  for usuario in
    select distinct usuario_id from public.leituras_scan
    union
    select distinct usuario_id from public.configuracoes_usuario
  loop
    perform public.recalcular_dados_usuario_ecoscan(usuario.usuario_id);
  end loop;
end;
$$;

create or replace view public.estatisticas_usuario
with (security_invoker = true)
as
select h.usuario_id,
       count(*)::bigint as quantidade_leituras,
       count(*) filter (where h.confirmado_pelo_usuario)::bigint as leituras_confirmadas,
       count(distinct nullif(h.categoria,''))::bigint as quantidade_categorias,
       coalesce((select sum(e.pontos)::bigint from public.eventos_pontos e where e.usuario_id = h.usuario_id),0) as ecopontos,
       min(h.analisado_em) as primeira_leitura_em,
       max(h.analisado_em) as ultima_leitura_em
from public.historico_leituras_usuario h
group by h.usuario_id;
grant select on public.estatisticas_usuario to authenticated;

create or replace function public.buscar_objeto_ecoscan(p_rotulo text)
returns jsonb language sql stable security invoker set search_path = '' as $$
with entrada as (select public.normalizar_texto_ecoscan(p_rotulo) as valor),
correspondencias as (
  select distinct o.objeto_id, v.variante_id,
    case when s.sinonimo_normalizado = e.valor then 1
         when public.normalizar_texto_ecoscan(o.nome) = e.valor then 2 else 3 end as prioridade,
    to_jsonb(o) || jsonb_build_object(
      'variante_id',v.variante_id,
      'nome_material',coalesce(v.nome_material,o.nome_material,m.nome),
      'categoria',coalesce(v.categoria,o.categoria,m.categoria),
      'cor_lixeira',coalesce(v.cor_lixeira,o.cor_lixeira,m.cor_lixeira),
      'recomendacao',coalesce(v.recomendacao,o.recomendacao,m.orientacao),
      'instrucoes_preparo',coalesce(v.instrucoes_preparo,o.instrucoes_preparo,m.orientacao)
    ) as resultado
  from public.objetos o cross join entrada e
  left join public.sinonimos_objeto s on s.objeto_id=o.objeto_id and s.ativo and s.sinonimo_normalizado=e.valor
  left join public.variantes_objeto v on v.variante_id=s.variante_id
  left join public.materiais m on m.material_id=coalesce(v.material_id,o.material_id)
  where o.ativo and e.valor <> '' and (
    (s.sinonimo_normalizado=e.valor and (not o.ambiguo or v.variante_id is not null))
    or (not o.ambiguo and public.normalizar_texto_ecoscan(o.nome)=e.valor)
    or (not o.ambiguo and public.normalizar_texto_ecoscan(o.classe_deteccao)=e.valor)
  )
), melhores as (select resultado from correspondencias where prioridade=(select min(prioridade) from correspondencias))
select case when count(*)=1 then jsonb_agg(resultado)->0 else null end from melhores;
$$;
revoke all on function public.buscar_objeto_ecoscan(text) from public;
grant execute on function public.buscar_objeto_ecoscan(text) to anon, authenticated;

drop function if exists public.find_ecoscan_object(text);
drop function if exists public.ecoscan_normalize_alias(text);

-- Regras de acesso com nomes em português; a identidade sempre vem do token Auth.
alter table public.perfis enable row level security;
alter table public.configuracoes_usuario enable row level security;
alter table public.materiais enable row level security;
alter table public.objetos enable row level security;
alter table public.variantes_objeto enable row level security;
alter table public.sinonimos_objeto enable row level security;
alter table public.pontos_ecologicos enable row level security;
alter table public.materiais_ponto_ecologico enable row level security;
alter table public.classes_yoloe enable row level security;
alter table public.leituras_scan enable row level security;
alter table public.exclusoes_leitura enable row level security;
alter table public.amostras_treinamento enable row level security;
alter table public.versoes_modelo enable row level security;
alter table public.conquistas enable row level security;
alter table public.conquistas_usuario enable row level security;
alter table public.eventos_pontos enable row level security;

drop policy if exists profiles_own_read on public.perfis;
drop policy if exists profiles_own_update on public.perfis;
drop policy if exists perfis_proprios_consulta on public.perfis;
create policy perfis_proprios_consulta on public.perfis for select to authenticated using ((select auth.uid())=usuario_id);
create policy perfis_proprios_alteracao on public.perfis for update to authenticated using ((select auth.uid())=usuario_id) with check ((select auth.uid())=usuario_id);
grant select, update on public.perfis to authenticated;

drop policy if exists pontos_ecologicos_publicos on public.pontos_ecologicos;
drop policy if exists ecopoints_public_read on public.pontos_ecologicos;
create policy pontos_ecologicos_publicos on public.pontos_ecologicos for select to anon, authenticated using (ativo);
drop policy if exists materiais_ponto_publicos on public.materiais_ponto_ecologico;
create policy materiais_ponto_publicos on public.materiais_ponto_ecologico for select to anon, authenticated using (
  exists(select 1 from public.pontos_ecologicos p where p.ponto_id=materiais_ponto_ecologico.ponto_id and p.ativo)
);
drop policy if exists materiais_publicos on public.materiais;
create policy materiais_publicos on public.materiais for select to anon, authenticated using (ativo);
drop policy if exists objetos_publicos on public.objetos;
drop policy if exists objects_public_read on public.objetos;
create policy objetos_publicos on public.objetos for select to anon, authenticated using (ativo);
drop policy if exists variantes_publicas on public.variantes_objeto;
drop policy if exists variants_public_read on public.variantes_objeto;
create policy variantes_publicas on public.variantes_objeto for select to anon, authenticated using (
  exists(select 1 from public.objetos o where o.objeto_id=variantes_objeto.objeto_id and o.ativo)
);
drop policy if exists sinonimos_publicos on public.sinonimos_objeto;
drop policy if exists aliases_public_read on public.sinonimos_objeto;
create policy sinonimos_publicos on public.sinonimos_objeto for select to anon, authenticated using (ativo);
drop policy if exists classes_yoloe_publicas on public.classes_yoloe;
create policy classes_yoloe_publicas on public.classes_yoloe for select to anon, authenticated using (ativa);
grant select on public.pontos_ecologicos, public.materiais_ponto_ecologico,
  public.materiais, public.objetos, public.variantes_objeto,
  public.sinonimos_objeto, public.classes_yoloe to anon, authenticated;

drop policy if exists fato_scan_own_read on public.leituras_scan;
drop policy if exists fato_scan_own_insert on public.leituras_scan;
drop policy if exists fato_scan_own_update on public.leituras_scan;
drop policy if exists fato_scan_own_delete on public.leituras_scan;
create policy leituras_proprias_consulta on public.leituras_scan for select to authenticated using ((select auth.uid())=usuario_id);
create policy leituras_proprias_inclusao on public.leituras_scan for insert to authenticated with check ((select auth.uid())=usuario_id);
create policy leituras_proprias_alteracao on public.leituras_scan for update to authenticated using ((select auth.uid())=usuario_id) with check ((select auth.uid())=usuario_id);
create policy leituras_proprias_exclusao on public.leituras_scan for delete to authenticated using ((select auth.uid())=usuario_id);
grant select, insert, update, delete on public.leituras_scan to authenticated;

drop policy if exists fato_scan_deletions_own_read on public.exclusoes_leitura;
drop policy if exists fato_scan_deletions_own_insert on public.exclusoes_leitura;
drop policy if exists fato_scan_deletions_own_update on public.exclusoes_leitura;
create policy exclusoes_proprias_consulta on public.exclusoes_leitura for select to authenticated using ((select auth.uid())=usuario_id);
create policy exclusoes_proprias_inclusao on public.exclusoes_leitura for insert to authenticated with check ((select auth.uid())=usuario_id);
create policy exclusoes_proprias_alteracao on public.exclusoes_leitura for update to authenticated using ((select auth.uid())=usuario_id) with check ((select auth.uid())=usuario_id);
grant select, insert, update on public.exclusoes_leitura to authenticated;

drop policy if exists "users read their EcoScan training samples" on public.amostras_treinamento;
drop policy if exists "users create their EcoScan training samples" on public.amostras_treinamento;
drop policy if exists "users retry pending EcoScan training samples" on public.amostras_treinamento;
create policy amostras_proprias_consulta on public.amostras_treinamento for select to authenticated using (auth.uid()=usuario_id);
create policy amostras_com_consentimento on public.amostras_treinamento for insert to authenticated with check (
  auth.uid()=usuario_id and situacao='pendente' and rotulo_confirmado is null and anotacoes='[]'::jsonb
);
create policy amostras_pendentes_alteracao on public.amostras_treinamento for update to authenticated
using (auth.uid()=usuario_id and situacao='pendente')
with check (auth.uid()=usuario_id and situacao='pendente' and rotulo_confirmado is null and anotacoes='[]'::jsonb);
grant select, insert, update on public.amostras_treinamento to authenticated;

drop policy if exists "users upload their own EcoScan training images" on storage.objects;
drop policy if exists "users replace their own pending training images" on storage.objects;
drop policy if exists "users read their own EcoScan training images" on storage.objects;
create policy imagens_de_treinamento_insercao on storage.objects for insert to authenticated
with check (bucket_id='ecoscan-training' and (storage.foldername(name))[1]=auth.uid()::text);
create policy imagens_de_treinamento_alteracao on storage.objects for update to authenticated
using (bucket_id='ecoscan-training' and (storage.foldername(name))[1]=auth.uid()::text)
with check (bucket_id='ecoscan-training' and (storage.foldername(name))[1]=auth.uid()::text);
create policy imagens_de_treinamento_consulta on storage.objects for select to authenticated
using (bucket_id='ecoscan-training' and (storage.foldername(name))[1]=auth.uid()::text);

drop policy if exists "authenticated users read active EcoScan models" on public.versoes_modelo;
create policy versoes_ativas_consulta on public.versoes_modelo for select to authenticated using (ativa);
grant select on public.versoes_modelo to authenticated;
drop policy if exists "authenticated users download released EcoScan models" on storage.objects;
create policy modelos_publicados_download on storage.objects for select to authenticated using (
  bucket_id='ecoscan-models' and exists (
    select 1 from public.versoes_modelo versao
    where versao.id_bucket=storage.objects.bucket_id
      and versao.caminho_arquivo=storage.objects.name and versao.ativa
  )
);

drop policy if exists conquistas_ativas_consulta on public.conquistas;
create policy conquistas_ativas_consulta on public.conquistas for select to anon, authenticated using (ativa);
grant select on public.conquistas to anon, authenticated;
drop policy if exists conquistas_usuario_proprias_consulta on public.conquistas_usuario;
create policy conquistas_usuario_proprias_consulta on public.conquistas_usuario for select to authenticated using ((select auth.uid())=usuario_id);
grant select on public.conquistas_usuario to authenticated;
drop policy if exists eventos_pontos_proprios_consulta on public.eventos_pontos;
create policy eventos_pontos_proprios_consulta on public.eventos_pontos for select to authenticated using ((select auth.uid())=usuario_id);
grant select on public.eventos_pontos to authenticated;

drop policy if exists configuracoes_proprias_consulta on public.configuracoes_usuario;
drop policy if exists configuracoes_proprias_inclusao on public.configuracoes_usuario;
drop policy if exists configuracoes_proprias_alteracao on public.configuracoes_usuario;
create policy configuracoes_proprias_consulta on public.configuracoes_usuario for select to authenticated using ((select auth.uid())=usuario_id);
create policy configuracoes_proprias_inclusao on public.configuracoes_usuario for insert to authenticated with check ((select auth.uid())=usuario_id);
create policy configuracoes_proprias_alteracao on public.configuracoes_usuario for update to authenticated using ((select auth.uid())=usuario_id) with check ((select auth.uid())=usuario_id);
grant select, insert, update on public.configuracoes_usuario to authenticated;

create index if not exists leituras_usuario_data_idx on public.leituras_scan(usuario_id, analisado_em desc);
create index if not exists leituras_objeto_idx on public.leituras_scan(objeto_id) where objeto_id is not null;
create index if not exists sinonimos_objeto_busca_idx on public.sinonimos_objeto(sinonimo_normalizado);
create index if not exists pontos_localizacao_gist on public.pontos_ecologicos using gist(localizacao_geografica);

notify pgrst, 'reload schema';
-- <<< MIGRATION 202610160001_schema_ptbr.sql
commit;

select 'objetos' as conjunto, count(*) as quantidade from public.objetos;
select 'materiais' as conjunto, count(*) as quantidade from public.materiais where ativo;
select 'variantes' as conjunto, count(*) as quantidade from public.variantes_objeto;
select 'sinonimos' as conjunto, count(*) as quantidade from public.sinonimos_objeto where ativo;
select 'classes_yoloe' as conjunto, count(*) as quantidade from public.classes_yoloe;
select 'pontos_ecologicos_geosampa' as conjunto, count(*) as quantidade from public.pontos_ecologicos where fonte = 'geosampa' and ativo;
select 'aceites_de_materiais' as conjunto, count(*) as quantidade from public.materiais_ponto_ecologico;
select public.buscar_objeto_ecoscan('bottle') is null as classe_ambigua_nao_classificada_sozinha;

-- Backup privado de imagens do historico e da foto de perfil por conta.
alter table public.leituras_scan
  add column if not exists caminho_imagem text;
alter table public.configuracoes_usuario
  add column if not exists caminho_foto_perfil text;

update public.leituras_scan
set nome_objeto = case lower(trim(coalesce(categoria, '')))
  when 'plástico' then 'Plásticos'
  when 'plastico' then 'Plásticos'
  when 'papel' then 'Papel e papelão'
  when 'papelão' then 'Papel e papelão'
  when 'papelao' then 'Papel e papelão'
  when 'vidro' then 'Vidros'
  when 'metal' then 'Metais'
  when 'orgânico' then 'Orgânicos'
  when 'organico' then 'Orgânicos'
  when 'rejeito' then 'Resíduo não reciclável'
  when 'resíduo não reciclável' then 'Resíduo não reciclável'
  when 'residuo nao reciclavel' then 'Resíduo não reciclável'
  when 'eletrônico' then 'Eletrônicos'
  when 'eletronico' then 'Eletrônicos'
  when 'descarte especial' then 'Resíduo especial'
  else coalesce(nullif(trim(categoria), ''), nome_material)
end,
rotulo_detectado = null
where rotulo_detectado is not null
   or nome_objeto is distinct from (case lower(trim(coalesce(categoria, '')))
     when 'plástico' then 'Plásticos'
     when 'plastico' then 'Plásticos'
     when 'papel' then 'Papel e papelão'
     when 'papelão' then 'Papel e papelão'
     when 'papelao' then 'Papel e papelão'
     when 'vidro' then 'Vidros'
     when 'metal' then 'Metais'
     when 'orgânico' then 'Orgânicos'
     when 'organico' then 'Orgânicos'
     when 'rejeito' then 'Resíduo não reciclável'
     when 'resíduo não reciclável' then 'Resíduo não reciclável'
     when 'residuo nao reciclavel' then 'Resíduo não reciclável'
     when 'eletrônico' then 'Eletrônicos'
     when 'eletronico' then 'Eletrônicos'
     when 'descarte especial' then 'Resíduo especial'
     else coalesce(nullif(trim(categoria), ''), nome_material)
   end);

create or replace view public.historico_leituras_usuario
with (security_invoker = true)
as
select leitura.*
from public.leituras_scan leitura
where not exists (
  select 1 from public.exclusoes_leitura exclusao
  where exclusao.usuario_id = leitura.usuario_id
    and exclusao.id_leitura_cliente = leitura.id_leitura_cliente
);
grant select on public.historico_leituras_usuario to authenticated;

insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
)
values (
  'ecoscan-account-data', 'ecoscan-account-data', false, 52428800,
  array['image/jpeg', 'image/png', 'image/webp']::text[]
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "EcoScan: ler arquivos da propria conta" on storage.objects;
create policy "EcoScan: ler arquivos da propria conta" on storage.objects
for select to authenticated using (
  bucket_id = 'ecoscan-account-data'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);
drop policy if exists "EcoScan: enviar arquivos para a propria conta" on storage.objects;
create policy "EcoScan: enviar arquivos para a propria conta" on storage.objects
for insert to authenticated with check (
  bucket_id = 'ecoscan-account-data'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);
drop policy if exists "EcoScan: atualizar arquivos da propria conta" on storage.objects;
create policy "EcoScan: atualizar arquivos da propria conta" on storage.objects
for update to authenticated using (
  bucket_id = 'ecoscan-account-data'
  and (storage.foldername(name))[1] = (select auth.uid())::text
) with check (
  bucket_id = 'ecoscan-account-data'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);
drop policy if exists "EcoScan: excluir arquivos da propria conta" on storage.objects;
create policy "EcoScan: excluir arquivos da propria conta" on storage.objects
for delete to authenticated using (
  bucket_id = 'ecoscan-account-data'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

notify pgrst, 'reload schema';
