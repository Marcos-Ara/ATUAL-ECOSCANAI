# Salvar correções na conta EcoScan

Para quem já instalou o banco do EcoScan e executou a atualização do bucket
privado (`202610210001_backup_privado_conta.sql`), execute uma vez no SQL
Editor do mesmo projeto Supabase:

`migrations/202610220001_correcoes_persistentes.sql`

Essa migração cria `public.correcoes_usuario`, com acesso restrito à conta
autenticada, para sincronizar correções e fotos no bucket privado
`ecoscan-account-data`. Ela não envia a imagem para treinamento. O envio para
`ecoscan-training` e `public.amostras_treinamento` continua dependendo do
consentimento explícito em Configurações.

Se ainda não instalou o bucket privado `ecoscan-account-data`, execute primeiro
`migrations/202610210001_backup_privado_conta.sql`.

Não execute novamente o instalador do zero em um projeto que já está em uso.
