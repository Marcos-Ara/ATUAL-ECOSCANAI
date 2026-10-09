# Revisar correções do EcoScan no Supabase

## 1. Corrigir o erro “Bucket not found”

No painel do projeto Supabase, abra **SQL Editor**, crie uma consulta, cole o conteúdo completo de `migrations/202610080001_learning_reports.sql` e execute. A migração cria ou repara o bucket privado `ecoscan-training`, a tabela `public.ecoscan_training_samples` e as políticas para cada pessoa enviar e ver apenas suas próprias amostras.

Não torne o bucket público: as fotos de correção ficam privadas.

Se o app continuar mostrando `Bucket not found`/404 depois da migração, confira **Project Settings → API → Project URL** no painel e compare com `SUPABASE_URL` em `config/mobile.json`. O SQL e o app precisam apontar para o mesmo projeto. Em seguida, confirme em **Storage → Buckets** que existe um bucket chamado exatamente `ecoscan-training` e recompile o app com esse mesmo `config/mobile.json`.

Também é possível confirmar o bucket no SQL Editor:

```sql
select id, name, public, file_size_limit
from storage.buckets
where id = 'ecoscan-training';
```

O resultado esperado é uma linha com `id = ecoscan-training` e `public = false`.

## 2. Enviar uma correção pelo aplicativo

1. Entre no app com uma conta autenticada (o modo visitante não envia).
2. No Scan, use **Fotografar** e, quando a identificação estiver errada ou ausente, toque em **Corrigir identificação**.
3. Informe o objeto correto, escolha o material/destino e confirme.
4. Em **Configurações → Amostras locais para melhoria**, toque em **Enviar com consentimento**.
5. No Supabase, abra **Table Editor → ecoscan_training_samples**. A linha deve aparecer com `status = pending`, o relato em `user_reported_label` / `user_reported_bin` e o caminho da foto em `storage_path`.

Se o upload falhar, as amostras permanecem no aparelho. Depois de executar a migração, tente enviar novamente.

## 3. Ver as correções pendentes

No SQL Editor, rode:

```sql
select
  user_id,
  client_sample_id,
  user_reported_label,
  user_reported_bin,
  report_note,
  original_label,
  original_confidence,
  storage_path,
  status,
  created_at
from public.ecoscan_training_samples
where status = 'pending'
order by created_at desc;
```

Para abrir a imagem, entre em **Storage → ecoscan-training** e localize o objeto pelo caminho da coluna `storage_path`. O bucket é privado; faça a revisão pelo painel administrativo do projeto.

## 4. Aprovar ou rejeitar

Confira a imagem antes de aprovar. Use `user_id` e `client_sample_id` da linha, e preencha os valores confirmados pelo revisor:

```sql
update public.ecoscan_training_samples
set status = 'approved',
    verified_label = 'RÓTULO CONFIRMADO',
    verified_bin = 'MATERIAL OU DESTINO CONFIRMADO',
    reviewed_at = now()
where user_id = 'UUID_DA_LINHA'::uuid
  and client_sample_id = 'ID_DA_LINHA'
  and status = 'pending';
```

Para rejeitar, rode:

```sql
update public.ecoscan_training_samples
set status = 'rejected',
    reviewed_at = now()
where user_id = 'UUID_DA_LINHA'::uuid
  and client_sample_id = 'ID_DA_LINHA'
  and status = 'pending';
```

Troque os valores de exemplo pelos dados exatos da linha. O estado aprovado registra uma revisão, mas **não treina nem publica um modelo automaticamente**.

## 5. Preparar a amostra para treinamento YOLO-E

O exportador de dataset usa apenas linhas aprovadas que também tenham `annotations` com caixas desenhadas e normalizadas entre 0 e 1. Exemplo de estrutura (as coordenadas abaixo são apenas ilustrativas; revise a foto e ajuste-as):

```sql
update public.ecoscan_training_samples
set annotations = '[
  {"label":"RÓTULO CONFIRMADO","left":0.10,"top":0.10,"right":0.90,"bottom":0.90}
]'::jsonb
where user_id = 'UUID_DA_LINHA'::uuid
  and client_sample_id = 'ID_DA_LINHA'
  and status = 'approved';
```

`left` e `top` são o canto superior esquerdo da caixa; `right` e `bottom` são o canto inferior direito. O exportador ignora amostras sem caixas válidas. Depois é preciso exportar o dataset, treinar, avaliar e publicar explicitamente novos pesos; aprovar uma correção por si só não muda o comportamento do app.
