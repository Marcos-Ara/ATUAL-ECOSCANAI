# Correções salvas sem foto

As correções do usuário são armazenadas em `correcoes_usuario` no Supabase. A foto é opcional. Para banco já instalado, aplique uma vez `migrations/202610270001_correcoes_sem_foto.sql` no SQL Editor.

O envio para `ecoscan-training` continua exigindo uma imagem e consentimento explícito. Salvar uma correção no perfil não envia amostra para treinamento e não altera os pesos do YOLO.
