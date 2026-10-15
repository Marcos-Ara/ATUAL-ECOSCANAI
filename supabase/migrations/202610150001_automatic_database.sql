-- EcoScan 3.4.9: first automatic account-data sync and safe catalog resolution.
-- Run after 202610080001_learning_reports.sql.
begin;

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

commit;
