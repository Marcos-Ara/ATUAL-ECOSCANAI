# Revisar amostras de correção no Supabase

As imagens de correção ficam privadas no bucket `ecoscan-training`. O app só envia uma amostra depois que a pessoa toca em **Enviar com consentimento**. Cada amostra entra como `pendente`; esse envio não inicia o treinamento.

## Conferir se o bucket existe

No Supabase, abra **Storage → Buckets** e confira se existe `ecoscan-training` com acesso privado. Também é possível consultar no SQL Editor:

```sql
select id, name, public, file_size_limit
from storage.buckets
where id = 'ecoscan-training';
```

O resultado esperado é uma linha com `id = ecoscan-training` e `public = false`. Se o bucket não existir, rode a instalação inicial `supabase/ECOSCAN_SUPABASE_NOVO.sql` somente se esse banco ainda não tiver recebido a instalação. Para um banco já instalado, confira o histórico das migrações antes de aplicar uma correção.

## Ver amostras pendentes

No Supabase, abra **Table Editor → amostras_treinamento** ou rode:

```sql
select
  usuario_id,
  id_amostra_cliente,
  rotulo_informado_usuario,
  lixeira_informada_usuario,
  observacao,
  rotulo_original,
  confianca_original,
  caminho_arquivo,
  situacao,
  criado_em
from public.amostras_treinamento
where situacao = 'pendente'
order by criado_em desc;
```

Localize a imagem em **Storage → ecoscan-training** usando o caminho de `caminho_arquivo`. A primeira pasta do caminho corresponde à conta autenticada. O bucket não deve ser tornado público.

## Aprovar ou rejeitar após conferir a foto

Use os valores reais de `usuario_id` e `id_amostra_cliente` da linha. Para aprovar, informe o rótulo e o destino revisados:

```sql
update public.amostras_treinamento
set situacao = 'aprovada',
    rotulo_confirmado = 'RÓTULO REVISADO',
    lixeira_confirmada = 'MATERIAL OU DESTINO REVISADO',
    revisado_em = now()
where usuario_id = 'UUID_DA_LINHA'::uuid
  and id_amostra_cliente = 'ID_DA_LINHA'
  and situacao = 'pendente';
```

Para rejeitar:

```sql
update public.amostras_treinamento
set situacao = 'rejeitada',
    revisado_em = now()
where usuario_id = 'UUID_DA_LINHA'::uuid
  and id_amostra_cliente = 'ID_DA_LINHA'
  and situacao = 'pendente';
```

Troque os textos de exemplo pelos dados exatos da linha. A política do banco impede o app comum de aprovar ou rejeitar amostras; faça a revisão usando o painel administrativo.

## Anotar uma caixa para treinamento

Só amostras aprovadas com uma caixa válida podem seguir para exportação. Revise a posição na foto: as coordenadas são normalizadas de 0 a 1.

```sql
update public.amostras_treinamento
set anotacoes = '[
  {"rotulo":"RÓTULO REVISADO","esquerda":0.10,"topo":0.10,"direita":0.90,"base":0.90}
]'::jsonb
where usuario_id = 'UUID_DA_LINHA'::uuid
  and id_amostra_cliente = 'ID_DA_LINHA'
  and situacao = 'aprovada';
```

As coordenadas acima são apenas ilustrativas; desenhe a caixa correta e ajuste os números. Depois é necessário exportar o conjunto de dados, treinar, avaliar e publicar explicitamente os novos pesos. O banco não faz essas etapas sozinho.
