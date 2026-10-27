# EcoScan AI — Flutter, Supabase e Firebase

Este pacote contém o app, o catálogo de materiais, as classes YOLO-E, os EcoPontos GeoSampa e a instalação inicial do banco em português.

O login existente continua no Supabase. Com uma conta, o app sincroniza leituras, fotos, correções, preferências, perfil e conquistas com o Supabase e, quando configurado, faz também uma cópia privada no Firebase Firestore e Cloud Storage. O ID da conta Supabase é validado por uma Edge Function e reutilizado como UID Firebase; assim não são criadas contas duplicadas. Visitantes sem conta continuam usando o armazenamento do aparelho.

Cada alteração importante é guardada primeiro numa fila local e enviada aos serviços quando há conexão. A entrada não espera a restauração da nuvem: a tela principal abre e a conta sincroniza em segundo plano, com novas tentativas ao voltar ao app e enquanto ele estiver aberto. Com o Firebase configurado, leituras e correções já confirmadas são removidas da cópia completa no aparelho; os itens continuam visíveis durante a sessão e são restaurados da nuvem ao entrar novamente. Uma ação ainda pendente depende do aparelho até ser enviada. Visitantes sem conta continuam com os dados no dispositivo. Ao pressionar **Voltar** na tela inicial, aparece **Salvar e sair**; no Android, ele tenta enviar os dados por até 12 segundos e encerra mesmo se a rede falhar, mantendo as ações pendentes no aparelho para a próxima sincronização.

Na câmera ao vivo, o controle de zoom aproxima a imagem e limita as detecções à área visível. Toque numa caixa para classificar e manter o foco naquele objeto; use “Voltar a detectar automaticamente” para retomar a seleção automática.

## Abrir e executar no Windows

1. Extraia o ZIP e abra no VS Code a pasta `ATUAL-ECOSCANAI`, que contém `pubspec.yaml`.
2. No PowerShell, entre nessa pasta e rode:

```powershell
$env:FLUTTER_ROOT = 'C:\Users\ANHANGUERA\develop\flutter'
$flutter = Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat'
& $flutter pub get
& $flutter run -d chrome --web-hostname localhost --web-port 7357 --dart-define-from-file=config/mobile.json
```

Use o Flutter que existe no seu computador; ajuste `FLUTTER_ROOT` se o caminho for diferente. Para desenvolvimento, abra o terminal na pasta do projeto, não na pasta acima.

## Instalar o banco do zero

O Supabase continua responsável pelo login e pelos recursos já existentes, incluindo catálogo, EcoPontos e revisão de amostras. O Firebase mantém cópia da conta no Firestore e as fotos privadas no Cloud Storage. O Hosting Firebase continua hospedando a versão Web.

1. Siga `supabase/INSTALAR_BANCO_DO_ZERO.md`.
2. Execute o arquivo `supabase/ECOSCAN_SUPABASE_NOVO.sql` uma vez no SQL Editor do projeto Supabase configurado em `config/mobile.json`.
3. Gere e publique a Web/APK com esta mesma base. Uma versão antiga do app usa os nomes antigos das tabelas e não funcionará com o esquema final em português.

O arquivo SQL consolidado instala as tabelas, dados de catálogo, políticas de acesso e buckets privados. Não rode também todas as migrações individuais. Se o projeto já recebeu um SQL anterior, não repita a instalação inicial por cima.

### Projeto que já está instalado

Antes de instalar, confira se `supabase/migrations/202610220001_correcoes_persistentes.sql` e `supabase/migrations/202610210001_backup_privado_conta.sql` já foram aplicadas. A versão 3.4.22 não acrescenta alterações SQL no Supabase. Rode `supabase/VERIFICAR_SUPABASE.sql` no SQL Editor para conferir tabelas, fotos e políticas; esse diagnóstico é somente leitura. Veja `supabase/INSTRUCOES_BACKUP_PRIVADO.md`. As conquistas são calculadas pelo banco a partir das leituras e configurações da conta.

## O que sincroniza

- O Auth mantém `perfis` atualizado com nome e e-mail da conta.
- Leituras salvas, fotos e localização dessas leituras, foto de perfil, exclusões e preferências de tema, sons, avisos e mapa sincronizam por conta. Com Firebase configurado, o aparelho guarda somente a fila de leituras e correções ainda não confirmadas; a restauração de dados já sincronizados requer conexão. Ao entrar com uma conta, leituras feitas como visitante no mesmo aparelho são transferidas para ela.
- `eventos_pontos`, `conquistas_usuario` e `estatisticas_usuario` continuam calculados pelo Supabase. O Firebase guarda as conquistas recebidas pelo app e os dados necessários para restaurar a conta; a pontuação continua sendo recalculada a partir das leituras.
- O mapa atualiza os EcoPontos pelo Supabase e conserva um cache local.
- O app tenta o catálogo remoto quando o catálogo instalado não resolve um rótulo. O resolvedor não escolhe material para um rótulo ambíguo sem variante específica.
- Fotos do histórico, do perfil e das correções são mantidas no bucket privado Supabase `ecoscan-account-data` e, quando o Firebase estiver ativado, também em caminhos privados por usuário no Cloud Storage. Enviar amostras para revisão e treinamento no bucket Supabase `ecoscan-training` exige consentimento explícito; corrigir ou salvar uma leitura não treina o YOLO automaticamente.
- O login Google exige o provedor Google configurado no painel Supabase e as URLs de retorno do app autorizadas. Veja `CONFIGURAR_LOGIN_GOOGLE.md`; isso é uma configuração de autenticação, não uma alteração SQL.
- A versão 3.4.22 abre sem esperar a restauração dos dados da conta e sincroniza em segundo plano sem exibir avisos repetidos. A tela de salvamento aparece somente quando a pessoa escolhe **Salvar e sair**. No Android, o app fecha após uma tentativa limitada de sincronização; o que não chegou à nuvem permanece na fila local.

O projeto Firebase atual estava configurado somente para Hosting. Por isso, a cópia no Firebase só entra em operação depois de habilitar Firestore e Storage, preencher os IDs públicos dos apps em `config/mobile.json`, publicar as regras e configurar a Edge Function. O passo a passo está em `FIREBASE_SETUP.md`. Nenhuma tabela, bucket ou autenticação do Supabase é removida. Os dados antigos do Supabase são copiados para o Firebase na primeira restauração bem-sucedida depois da configuração.

O app mantém um mecanismo próprio para ações pendentes e desativa o cache persistente adicional do Firestore. O progresso de conquistas é derivado das leituras; não existe atualmente um estado de jogo separado para migrar.

A detecção é feita pelo modelo local no aparelho. O banco não consegue comprovar que um cliente não modificado enviou uma identificação verdadeira. Aprovar uma amostra não treina nem troca o modelo automaticamente. Veja `supabase/REVISAR_AMOSTRAS.md`.

Os IDs `ecoscan-training` e `ecoscan-models` são nomes técnicos de buckets usados pelo app; mantenha-os exatamente assim. Os rótulos em inglês definidos pelo YOLO também precisam continuar iguais aos do modelo.

## Atualizar dados mais tarde

- Catálogo YOLO-E: ajuste os arquivos de dados e use `tool/sync_yoloe_catalog.py`; ele prepara uma migração incremental para o esquema atual.
- EcoPontos: atualize a exportação GeoSampa com `tool/import_geosampa.py`; o arquivo prepara uma migração incremental em português e atualiza o pacote de instalação inicial.
- Depois, aplique somente a nova migração no SQL Editor. O app busca a nova lista remota ao atualizar o mapa.
- Atualização de modelo YOLO exige revisão, avaliação, arquivo válido e publicação manual. A opção de baixar pesos do Supabase permanece desligada por padrão.

## Gerar a Web e o APK

Dentro da pasta do projeto:

```powershell
$env:FLUTTER_ROOT = 'C:\Users\ANHANGUERA\develop\flutter'
$flutter = Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat'
& $flutter pub get
& $flutter build web --release --no-web-resources-cdn --dart-define-from-file=config/mobile.json
& $flutter build apk --release --dart-define-from-file=config/mobile.json
```

O site compilado fica em `build/web`; o APK em `build/app/outputs/flutter-apk/app-release.apk`. Para publicar o site, rode `firebase.cmd deploy --only hosting` na raiz do projeto depois que a compilação Web terminar.

Na aba **Baixar** do site, o botão usa a URL HTTPS de `ECOSCAN_APK_DOWNLOAD_URL` em `config/mobile.json`. Troque apenas esse link ao publicar uma nova versão do APK e gere/publique a Web novamente.

## Credenciais

Os valores de Firebase em `config/mobile.json` são identificadores/chaves públicas do app. Nunca coloque `service_role`, o segredo do cliente OAuth ou a chave JSON da conta de serviço Firebase nesse arquivo, no código Flutter ou no ZIP. A chave de serviço Firebase deve ficar somente nos segredos da Edge Function do Supabase.
