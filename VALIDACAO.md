# Validação da base EcoScan 3.4.1

## Correções aplicadas

- Deep link único para autenticação móvel: `ecoscan://login-callback/`.
- `AuthSession` usa `BackendConfig.mobileAuthRedirect` como fonte única.
- `config/mobile.json` e `config/mobile.json.example` alinhados ao mesmo redirect.
- AndroidManifest configurado para `ecoscan://login-callback/`.
- iOS `CFBundleURLSchemes` configurado para `ecoscan`.
- Handler padrão de deep link do Flutter desativado no Android/iOS, pois `supabase_flutter` usa `app_links` internamente.
- Build `release` mantém `isMinifyEnabled = false` e `isShrinkResources = false` para evitar o crash observado envolvendo WorkManager/ML Kit/R8.
- `android/local.properties` aponta para `C:\Users\ANHANGUERA\develop\flutter`.
- Versão atualizada para `3.4.1+20`.
- Logs de crash e metadados gerados antigos foram removidos da entrega.

## Checagens estáticas executadas nesta entrega

- `pubspec.yaml` parseado com sucesso.
- Todos os JSONs da base parseados com sucesso.
- AndroidManifest e Info.plist parseados como XML.
- Assets declarados no pubspec existem.
- Imports Dart relativos de `lib/` apontam para arquivos existentes.
- Nenhuma referência restante a `io.supabase.ecoscan`.
- Nenhuma referência restante ao caminho antigo `Flutter SKP`.
- Redirect consistente entre Dart, config, Android e iOS.

## Configuração externa obrigatória no Supabase

Em **Authentication → URL Configuration → Redirect URLs**, mantenha:

`ecoscan://login-callback/`

Para Google, o provider precisa estar habilitado no Supabase com Client ID/Secret do Google Cloud, e o callback do Google Cloud deve apontar para:

`https://kekcfxoiyufskltnzlie.supabase.co/auth/v1/callback`

## Validação final no seu Windows

O ambiente usado para preparar este ZIP não possui o Flutter SDK, então a compilação Flutter não foi executada aqui. No seu PC, rode:

```powershell
cd "C:\Users\ANHANGUERA\Desktop\ATUAL ECOSCANAI"
.\tool\verify_base.ps1 -BuildReleaseApk
```

Esse script executa `flutter clean`, `flutter pub get`, `flutter analyze`, `flutter test` e o build APK release.

Depois teste uma confirmação de e-mail **nova ou reenviada**. Links antigos gerados antes da troca do redirect podem continuar apontando para o endereço antigo.
