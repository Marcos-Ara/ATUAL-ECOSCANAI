-- Migra o esquema inicial para nomes em português e completa o modelo relacional.
-- auth.users e storage.* são esquemas internos do Supabase e permanecem intactos.
begin;

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
commit;
