-- Preserve the name chosen in the app when Supabase refreshes Google metadata.
-- This is safe to apply to an existing EcoScan database.
begin;

create or replace function public.sincronizar_perfil_ecoscan()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  nome_do_provedor text;
begin
  nome_do_provedor := coalesce(
    nullif(btrim(new.raw_user_meta_data->>'full_name'), ''),
    nullif(btrim(new.raw_user_meta_data->>'name'), ''),
    ''
  );

  insert into public.perfis as perfil
    (usuario_id, email, nome_completo, atualizado_em)
  values
    (new.id, new.email, nome_do_provedor, now())
  on conflict (usuario_id) do update set
    email = excluded.email,
    nome_completo = case
      when nullif(btrim(perfil.nome_completo), '') is null
        then excluded.nome_completo
      else perfil.nome_completo
    end,
    atualizado_em = now();

  return new;
end;
$$;

notify pgrst, 'reload schema';
commit;
