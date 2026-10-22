-- Guarda correções de identificação na conta do usuário, separadas das
-- amostras enviadas para treinamento. O envio de treinamento continua exigindo
-- consentimento explícito em Configurações.

create table if not exists public.correcoes_usuario (
  usuario_id uuid not null references auth.users(id) on delete cascade,
  id_correcao_cliente text not null,
  caminho_imagem text not null,
  origem text not null default 'camera',
  mecanismo_deteccao text not null default 'unknown',
  deteccoes jsonb not null default '[]'::jsonb
    check (jsonb_typeof(deteccoes) = 'array'),
  rotulo_informado_usuario text not null,
  lixeira_informada_usuario text not null,
  observacao text,
  detectado_por_ia boolean not null default false,
  rotulo_original text,
  confianca_original double precision
    check (confianca_original is null or confianca_original between 0 and 1),
  enviada_para_revisao_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  primary key (usuario_id, id_correcao_cliente)
);

create index if not exists correcoes_usuario_data_idx
  on public.correcoes_usuario (usuario_id, criado_em desc);

alter table public.correcoes_usuario enable row level security;

drop policy if exists correcoes_proprias_consulta
  on public.correcoes_usuario;
create policy correcoes_proprias_consulta
on public.correcoes_usuario
for select to authenticated
using ((select auth.uid()) = usuario_id);

drop policy if exists correcoes_proprias_inclusao
  on public.correcoes_usuario;
create policy correcoes_proprias_inclusao
on public.correcoes_usuario
for insert to authenticated
with check ((select auth.uid()) = usuario_id);

drop policy if exists correcoes_proprias_alteracao
  on public.correcoes_usuario;
create policy correcoes_proprias_alteracao
on public.correcoes_usuario
for update to authenticated
using ((select auth.uid()) = usuario_id)
with check ((select auth.uid()) = usuario_id);

drop policy if exists correcoes_proprias_exclusao
  on public.correcoes_usuario;
create policy correcoes_proprias_exclusao
on public.correcoes_usuario
for delete to authenticated
using ((select auth.uid()) = usuario_id);

grant select, insert, update, delete
on public.correcoes_usuario to authenticated;

notify pgrst, 'reload schema';
