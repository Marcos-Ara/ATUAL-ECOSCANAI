# EcoScan AI — app Flutter, Supabase e Firebase

Este pacote inclui o app Android/Web, scanner YOLO-E local, leitura de materiais, histórico, correções, mapa de EcoPontos, conquistas e envio voluntário de amostras para revisão.

## Quem salva cada dado

- **Supabase é a fonte principal da conta.** Supabase Auth mantém login por e-mail/senha ou Google (a senha não é armazenada em texto simples pelo app); Postgres mantém leituras, correções, preferências e conquistas; o Storage privado `ecoscan-account-data` guarda fotos de perfil, leituras e correções. `ecoscan-training` recebe imagens somente quando a pessoa envia uma amostra com consentimento.
- **Firebase Hosting publica a versão Web.** Firestore guarda apenas um documento substituível com os metadados da ação mais recente da conta. Não recebe o histórico inteiro nem bytes de fotos; ele não substitui o Supabase.
- **Firebase Storage não é usado.** As fotos continuam no Storage privado do Supabase, e os registros sem foto também podem ser sincronizados. A correção que permite foto opcional precisa da migração indicada abaixo.
- **Sem conta:** os dados ficam neste aparelho. Se a pessoa estiver sem internet, ações de conta ainda não confirmadas ficam temporariamente em uma fila local mínima. Não é possível recuperar ações que nunca chegaram ao servidor após apagar ou desinstalar o app.

Cada leitura, correção, exclusão e preferência é enviada em segundo plano. Após confirmação do Supabase, o app apaga do cache local a cópia completa sincronizada e mantém apenas pendências. Ao entrar de novo com a mesma conta, os dados são restaurados do Supabase. Uma restauração não dispara novamente os avisos de conquistas já obtidas.

## Configuração Firebase

Os IDs Android e Web deste projeto já estão em `config/mobile.json`. A integração Firebase está desativada por padrão até habilitar Firebase Authentication e Firestore, publicar as regras e configurar a função segura de token no Supabase. Siga `FIREBASE_SETUP.md` para ativá-la. Não é necessário criar Firebase Storage ou habilitar faturamento para fotos.

O `google-services.json` fornecido foi usado como fonte dos identificadores públicos. Este app inicializa o Firebase com `FirebaseOptions` e `--dart-define-from-file`; não precisa mover esse JSON para `android/app` nem aplicar o plug-in Gradle Google Services. Não inclua chave privada de conta de serviço no app ou no ZIP.

## Supabase já instalado

A exportação de esquema enviada serviu apenas para conferência e não foi executada. Não remova tabelas ou buckets existentes. Para permitir salvar correções sem foto, aplique **uma vez** no SQL Editor do Supabase a migração `supabase/migrations/202610270001_correcoes_sem_foto.sql`. Ela só torna `correcoes_usuario.caminho_imagem` opcional e atualiza o cache do esquema. Não execute o SQL de instalação inicial em um banco já usado.

Para um projeto Supabase realmente novo, siga `supabase/INSTALAR_BANCO_DO_ZERO.md` e use o SQL consolidado atualizado. A aprovação de amostra não treina o YOLO automaticamente: revisão, treinamento, avaliação e publicação do modelo continuam sendo etapas separadas.

## Abrir e testar no Windows

Extraia o ZIP e abra a pasta que contém `pubspec.yaml`. No PowerShell, ajuste `FLUTTER_ROOT` para a instalação Flutter do computador e rode:

```powershell
$env:FLUTTER_ROOT = 'C:\Users\ANHANGUERA\develop\flutter'
$flutter = Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat'
& $flutter pub get
& $flutter analyze
& $flutter test
```

Para gerar Android e Web:

```powershell
& $flutter build apk --release --dart-define-from-file=config/mobile.json
& $flutter build web --release --no-web-resources-cdn --dart-define-from-file=config/mobile.json
```

O APK sai em `build/app/outputs/flutter-apk/app-release.apk`; a Web sai em `build/web`. Publique o Hosting após gerar a Web com `firebase.cmd deploy --only hosting --project ecoscanai-66682`.

O pacote é a fonte completa do app, não contém APK/Web pré-compilados. O link de download de APK fica em `ECOSCAN_APK_DOWNLOAD_URL` no arquivo de configuração.

## Segurança

A chave pública Supabase e as opções públicas Firebase ficam no arquivo de configuração do app. Nunca coloque `service_role`, segredo OAuth ou JSON privado de conta de serviço no projeto distribuído. `FIREBASE_SERVICE_ACCOUNT` deve existir somente nos segredos da Edge Function Supabase.
