# Atualizações necessárias do Supabase

O app EcoScan AI 3.4.22 salva o histórico e suas fotos, além da foto de perfil,
na conta conectada. Os arquivos ficam em um bucket privado; cada conta só pode
acessar arquivos dentro da própria pasta.

O app EcoScan AI 3.4.22 também sincroniza as correções e suas fotos para a
conta, sem enviá-las automaticamente para treinamento. Para isso, execute uma
vez `migrations/202610220001_correcoes_persistentes.sql` no mesmo projeto.
O envio para `ecoscan-training` continua dependendo do consentimento em
Configurações.

## Projeto Supabase que já está em uso

Esta versão mantém Supabase Auth, Postgres e Storage e adiciona cópia de conta
no Firebase Firestore e Cloud Storage, usando o mesmo ID validado do Supabase.
Não migre nem remova o Supabase. A fila offline é mantida pelo app até os
serviços configurados confirmarem cada envio; por isso não precisa de uma
tabela nova.

1. Abra o **SQL Editor** do mesmo projeto Supabase que o app utiliza.
2. Se ainda não executou a atualização anterior, rode
   `migrations/202610210001_backup_privado_conta.sql` uma vez.
3. Rode também `migrations/202610220001_correcoes_persistentes.sql` uma vez.
4. Instale o APK atualizado e entre com o mesmo Gmail que usava antes.

Depois das migrações, execute `VERIFICAR_SUPABASE.sql` no SQL Editor. Ele só
consulta o esquema e mostra `OK` ou `FALTA`; não altera nem apaga registros.
Para esta versão 3.4.22 não existe SQL de atualização novo. A ativação do
Firebase está descrita em `../FIREBASE_SETUP.md`.

Essa atualização acrescenta o caminho da imagem ao histórico, atualiza a visão
de leitura, cria o bucket privado `ecoscan-account-data` com regras por usuário
e troca rótulos de objeto nas leituras antigas pelos nomes das categorias. Ela
não apaga tabelas nem leituras. Não execute novamente o script completo de
instalação em um projeto já em uso.

## O que será recuperado

- Leituras salvas na conta, incluindo fotos, localização, histórico, pontos e conquistas
  calculados a partir das leituras.
- Preferências da conta e foto de perfil.
- Leituras feitas como visitante no mesmo aparelho são copiadas para a primeira
  conta conectada e entram na sincronização.

Uma desinstalação apaga dados que ainda existiam apenas no aparelho. Por isso,
leituras feitas sem internet ou antes de entrar em uma conta só podem ser
recuperadas se o aparelho ainda tiver esses dados.

As correções ficam na conta em armazenamento privado. As amostras pendentes de
treinamento continuam protegidas pela confirmação de consentimento em
**Configurações**. Elas não são enviadas automaticamente para treinamento nem
fazem o YOLO aprender assim que uma leitura é salva.
