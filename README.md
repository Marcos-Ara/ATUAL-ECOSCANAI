# EcoScan AI — base Flutter e Supabase

Este pacote contém o app, o catálogo de materiais, as classes YOLO-E, os EcoPontos GeoSampa e a instalação inicial do banco em português.

O histórico, as correções, as preferências e as conquistas da conta são sincronizados automaticamente. Ao abrir com uma conta, o app mostra a tela de carregamento até restaurar os dados do Supabase. As alterações são gravadas no aparelho imediatamente e sincronizadas com a conta; ao voltar do segundo plano, o app tenta enviar novamente qualquer alteração pendente. Uma conta visitante sem e-mail/Google só pode recuperar os dados que ainda estiverem neste aparelho.

O salvamento não espera uma tela de saída: Android e iOS podem encerrar o app sem dar tempo para essa tela aparecer. Por isso cada ação é gravada quando acontece, e o envio pendente também é tentado quando o app vai para o segundo plano.

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

Antes de instalar esta versão 3.4.18, execute `supabase/migrations/202610220001_correcoes_persistentes.sql` no SQL Editor. Se o bucket privado ainda não foi criado, execute também antes `supabase/migrations/202610210001_backup_privado_conta.sql`. Veja `supabase/INSTRUCOES_BACKUP_PRIVADO.md`. As migrações acrescentam o backup privado das correções e fotos sem apagar o banco atual. As conquistas existentes são lidas de `public.conquistas_usuario`, que já pertence ao esquema EcoScan.

## O que sincroniza

- O Auth mantém `perfis` atualizado com nome e e-mail da conta.
- Leituras salvas, fotos e localização dessas leituras, foto de perfil, exclusões e preferências de tema, sons, avisos e mapa sincronizam por conta. O app mantém uma cópia local para funcionar sem rede; ao entrar com uma conta, leituras feitas como visitante no mesmo aparelho são transferidas para ela.
- `eventos_pontos`, `conquistas_usuario` e `estatisticas_usuario` são calculados pelo banco; o app não pode gravar pontuação diretamente.
- O mapa atualiza os EcoPontos pelo Supabase e conserva um cache local.
- O app tenta o catálogo remoto quando o catálogo instalado não resolve um rótulo. O resolvedor não escolhe material para um rótulo ambíguo sem variante específica.
- Fotos do histórico, do perfil e das correções ficam no bucket privado `ecoscan-account-data`, com acesso restrito à própria conta. Enviar amostras para revisão e treinamento no bucket `ecoscan-training` exige consentimento explícito; corrigir ou salvar uma leitura não treina o YOLO automaticamente.

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
