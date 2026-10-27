-- Diagnóstico somente de leitura; não cria, altera nem remove dados.
-- Cada item deve retornar status = OK.
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
    'Tabela public.configuracoes_usuario',
    to_regclass('public.configuracoes_usuario') is not null,
    'Preferências e caminho da foto de perfil da conta'
  union all
  select
    'Tabela public.correcoes_usuario',
    to_regclass('public.correcoes_usuario') is not null,
    'Correções privadas e fotos guardadas sem envio automático para treino'
  union all
  select
    'Tabela public.conquistas_usuario',
    to_regclass('public.conquistas_usuario') is not null,
    'Conquistas calculadas no servidor a partir de leituras e configurações'
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
    'Coluna caminho_imagem em leituras_scan',
    exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'leituras_scan'
        and column_name = 'caminho_imagem'
    ),
    'Referência à foto privada da leitura no Storage'
  union all
  select
    'Coluna caminho_foto_perfil em configuracoes_usuario',
    exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'configuracoes_usuario'
        and column_name = 'caminho_foto_perfil'
    ),
    'Referência à foto de perfil privada no Storage'
  union all
  select
    'Colunas principais em correcoes_usuario',
    (
      select count(*) = 8
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'correcoes_usuario'
        and column_name in (
          'id_correcao_cliente', 'caminho_imagem', 'origem',
          'mecanismo_deteccao', 'deteccoes', 'rotulo_informado_usuario',
          'lixeira_informada_usuario', 'enviada_para_revisao_em'
        )
    ),
    'Dados da correção, foto e estado de envio para revisão'
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
    'Bucket privado ecoscan-account-data',
    exists (
      select 1 from storage.buckets
      where id = 'ecoscan-account-data' and public = false
    ),
    'Fotos de histórico, correções e perfil em armazenamento privado'
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
    'RLS habilitado nas tabelas da conta',
    (
      select count(*) = 4
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname in (
          'leituras_scan', 'exclusoes_leitura',
          'configuracoes_usuario', 'correcoes_usuario'
        )
        and c.relrowsecurity
    ),
    'Leituras, exclusões, configurações e correções isoladas por usuário'
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
    'Políticas próprias em correcoes_usuario',
    (
      select count(*) = 4
      from pg_policies
      where schemaname = 'public'
        and tablename = 'correcoes_usuario'
        and policyname in (
          'correcoes_proprias_consulta', 'correcoes_proprias_inclusao',
          'correcoes_proprias_alteracao', 'correcoes_proprias_exclusao'
        )
    ),
    'Cada pessoa acessa e altera somente as próprias correções'
  union all
  select
    'Políticas de acesso ao bucket da conta',
    (
      select count(*) = 4
      from pg_policies
      where schemaname = 'storage'
        and tablename = 'objects'
        and policyname in (
          'EcoScan: ler arquivos da propria conta',
          'EcoScan: enviar arquivos para a propria conta',
          'EcoScan: atualizar arquivos da propria conta',
          'EcoScan: excluir arquivos da propria conta'
        )
    ),
    'Cada conta acessa somente sua própria pasta de fotos'
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
