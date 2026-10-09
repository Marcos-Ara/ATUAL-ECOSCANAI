-- Prepares the private image bucket and correction table used by EcoScan.
begin;

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

commit;
