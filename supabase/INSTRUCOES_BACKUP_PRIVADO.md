# Atualização incremental do Supabase

O Supabase continua como autenticação e armazenamento principal do EcoScan AI. Esta versão usa as tabelas, políticas RLS e buckets Supabase existentes; não apague tabelas, usuários, fotos ou amostras.

Para um banco já em uso, aplique uma vez a migração `migrations/202610270001_correcoes_sem_foto.sql` no SQL Editor do projeto. Ela permite que `correcoes_usuario.caminho_imagem` seja nulo, para guardar uma correção feita sem foto. O restante dos campos e políticas permanece igual.

As fotos de perfil, leituras e correções continuam no bucket privado `ecoscan-account-data`. Amostras enviadas para revisão usam `ecoscan-training` e exigem consentimento explícito. O Firebase não recebe imagens nem histórico completo.

Não rode o SQL de instalação inicial por cima de um projeto existente e não execute o schema de referência enviado na conversa. Para conferir o banco sem alterá-lo, use `VERIFICAR_SUPABASE.sql`.

A restauração após reinstalar depende de entrar com a mesma conta Supabase e de os registros já terem sido confirmados no servidor. Ações ainda sem conexão ficam temporariamente no aparelho e não podem sobreviver à desinstalação antes do envio.
