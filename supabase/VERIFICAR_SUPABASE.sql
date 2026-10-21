-- Diagnóstico somente de leitura. Cada item deve retornar status = OK.
with checks (item, ok, esperado) as (
  select
    'Tabela public.leituras_scan',
    to_regclass('public.leituras_scan') is not null,
    'Metadados das leituras salvas'
  union all
  select
    'Tabela public.exclusoes_leitura',
    to_regclass('public.exclusoes_leitura') is not null,
    'Exclusões que impedem leituras apagadas de voltarem na sincronização'
  union all
  select
    'Tabela public.amostras_treinamento',
    to_regclass('public.amostras_treinamento') is not null,
    'Rótulos corrigidos e caminho da foto enviada com consentimento'
  union all
  select
    'View public.historico_leituras_usuario',
    to_regclass('public.historico_leituras_usuario') is not null,
    'Histórico filtrado usado pelo aplicativo para restaurar leituras'
  union all
  select
    'Coluna caminho_arquivo em amostras_treinamento',
    exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'amostras_treinamento'
        and column_name = 'caminho_arquivo'
    ),
    'Caminho para a imagem mantida no Storage'
  union all
  select
    'Bucket privado ecoscan-training',
    exists (
      select 1 from storage.buckets
      where id = 'ecoscan-training' and public = false
    ),
    'Bucket existente, privado e separado das tabelas SQL'
  union all
  select
    'RLS habilitado em leituras_scan',
    exists (
      select 1
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname = 'leituras_scan'
        and c.relrowsecurity
    ),
    'A conta só pode consultar e alterar as próprias leituras'
  union all
  select
    'Política de exclusão própria em leituras_scan',
    exists (
      select 1 from pg_policies
      where schemaname = 'public'
        and tablename = 'leituras_scan'
        and policyname = 'leituras_proprias_exclusao'
        and cmd = 'DELETE'
    ),
    'Permite apagar somente leituras da conta autenticada'
  union all
  select
    'Política de envio consentido em amostras_treinamento',
    exists (
      select 1 from pg_policies
      where schemaname = 'public'
        and tablename = 'amostras_treinamento'
        and policyname = 'amostras_com_consentimento'
        and cmd = 'INSERT'
    ),
    'Amostras entram pendentes, sem rótulo revisado ou anotação de treino'
  union all
  select
    'Política de upload próprio no Storage',
    exists (
      select 1 from pg_policies
      where schemaname = 'storage'
        and tablename = 'objects'
        and policyname = 'imagens_de_treinamento_insercao'
        and cmd = 'INSERT'
    ),
    'Cada conta só envia fotos para sua própria pasta do bucket privado'
)
select
  item,
  case when ok then 'OK' else 'FALTA' end as status,
  esperado
from checks
order by item;
