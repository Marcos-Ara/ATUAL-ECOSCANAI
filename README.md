# EcoScan AI — base Flutter e Supabase

Este pacote contém o app, o catálogo de materiais, as classes YOLO-E, os EcoPontos GeoSampa e a instalação inicial do banco em português.

O histórico, as fotos, as correções, as preferências e as conquistas da conta são sincronizados automaticamente. Ao entrar com uma conta, o app tenta restaurar os dados do Supabase antes de abrir. Se a conexão demorar, abre com os dados locais e continua sincronizando em segundo plano, mostrando o andamento. Visitantes sem conta usam o armazenamento do aparelho.

Cada alteração é gravada localmente assim que acontece. Em contas conectadas, o app envia alterações ao Supabase e tenta novamente ao retornar ao app. Ao pressionar **Voltar** na tela inicial, aparece a opção **Salvar e sair**; se estiver sem internet, a cópia local permanece guardada para uma nova tentativa. O sistema operacional ainda pode encerrar o app sem aviso, por isso a gravação imediata no aparelho é a proteção principal.

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

O banco e a autenticação ficam no **Supabase**. O Firebase é usado somente para hospedar o site Web.

1. Siga `supabase/INSTALAR_BANCO_DO_ZERO.md`.
2. Execute o arquivo `supabase/ECOSCAN_SUPABASE_NOVO.sql` uma vez no SQL Editor do projeto Supabase configurado em `config/mobile.json`.
3. Gere e publique a Web/APK com esta mesma base. Uma versão antiga do app usa os nomes antigos das tabelas e não funcionará com o esquema final em português.

O arquivo SQL consolidado instala as tabelas, dados de catálogo, políticas de acesso e buckets privados. Não rode também todas as migrações individuais. Se o projeto já recebeu um SQL anterior, não repita a instalação inicial por cima.

### Projeto que já está instalado

Antes da primeira instalação da versão 3.4.18 ou posterior, confira se `supabase/migrations/202610220001_correcoes_persistentes.sql` e `supabase/migrations/202610210001_backup_privado_conta.sql` já foram aplicadas. Esta versão 3.4.19 não acrescenta alterações SQL. Veja `supabase/INSTRUCOES_BACKUP_PRIVADO.md`. As conquistas são calculadas pelo banco a partir das leituras e configurações da conta.

## O que sincroniza

- O Auth mantém `perfis` atualizado com nome e e-mail da conta.
- Leituras salvas, fotos e localização dessas leituras, foto de perfil, exclusões e preferências de tema, sons, avisos e mapa sincronizam por conta. O app mantém uma cópia local para funcionar sem rede; ao entrar com uma conta, leituras feitas como visitante no mesmo aparelho são transferidas para ela.
- `eventos_pontos`, `conquistas_usuario` e `estatisticas_usuario` são calculados pelo banco; o app não pode gravar pontuação diretamente.
- O mapa atualiza os EcoPontos pelo Supabase e conserva um cache local.
- O app tenta o catálogo remoto quando o catálogo instalado não resolve um rótulo. O resolvedor não escolhe material para um rótulo ambíguo sem variante específica.
- Fotos do histórico, do perfil e das correções ficam no bucket privado `ecoscan-account-data`, com acesso restrito à própria conta. Enviar amostras para revisão e treinamento no bucket `ecoscan-training` exige consentimento explícito; corrigir ou salvar uma leitura não treina o YOLO automaticamente.
- O login Google exige o provedor Google configurado no painel Supabase e as URLs de retorno do app autorizadas. Veja `CONFIGURAR_LOGIN_GOOGLE.md`; isso é uma configuração de autenticação, não uma alteração SQL.
- A versão 3.4.19 abre automaticamente com os dados locais se a restauração da conta demorar; ela segue sincronizando e mostra o andamento dentro do app. No Android, **Voltar** na tela inicial abre a confirmação **Salvar e sair**.

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

O app usa somente a chave pública configurada no projeto. Nunca coloque `service_role` ou o segredo do cliente OAuth em `config/mobile.json`, código Flutter ou no ZIP. O segredo OAuth deve ficar apenas no painel do Supabase, na configuração do provedor Google.
