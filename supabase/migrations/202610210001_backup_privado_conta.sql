-- Backup privado do historico e da foto de perfil por conta autenticada.
-- Execute esta migration no SQL Editor do Supabase antes de usar o novo app.

alter table public.leituras_scan
  add column if not exists caminho_imagem text;

alter table public.configuracoes_usuario
  add column if not exists caminho_foto_perfil text;

-- O app apresenta e sincroniza categorias; remove rótulos de objetos das
-- leituras antigas sem alterar as amostras de treinamento consentidas.
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
  select 1
  from public.exclusoes_leitura exclusao
  where exclusao.usuario_id = leitura.usuario_id
    and exclusao.id_leitura_cliente = leitura.id_leitura_cliente
);

grant select on public.historico_leituras_usuario to authenticated;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'ecoscan-account-data',
  'ecoscan-account-data',
  false,
  52428800,
  array['image/jpeg', 'image/png', 'image/webp']::text[]
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "EcoScan: ler arquivos da propria conta"
  on storage.objects;
create policy "EcoScan: ler arquivos da propria conta"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'ecoscan-account-data'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "EcoScan: enviar arquivos para a propria conta"
  on storage.objects;
create policy "EcoScan: enviar arquivos para a propria conta"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'ecoscan-account-data'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "EcoScan: atualizar arquivos da propria conta"
  on storage.objects;
create policy "EcoScan: atualizar arquivos da propria conta"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'ecoscan-account-data'
  and (storage.foldername(name))[1] = (select auth.uid())::text
)
with check (
  bucket_id = 'ecoscan-account-data'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "EcoScan: excluir arquivos da propria conta"
  on storage.objects;
create policy "EcoScan: excluir arquivos da propria conta"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'ecoscan-account-data'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

notify pgrst, 'reload schema';
