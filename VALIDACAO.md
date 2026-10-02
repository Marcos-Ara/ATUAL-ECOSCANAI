# Validação da base EcoScan 3.4.2

## Alterações desta base

- Cadastro detecta resposta de conta já existente e volta para **Entrar**, sem abrir a tela de confirmação como se fosse uma conta nova.
- Tela de verificação não mostra mais **sessão expirada** apenas porque a confirmação ainda não criou uma sessão.
- Redirect móvel preservado em `ecoscan://login-callback/`.
- `profiles` passa a manter nome e e-mail automaticamente via trigger no Supabase.
- Nova tabela `public.fato_scan` registra as análises salvas por usuários autenticados com RLS por usuário.
- O app tenta enviar a análise ao banco no momento do salvamento e tenta reenviar o histórico local na próxima entrada da conta se houver falha de rede.
- EcoPontos centralizam automaticamente na localização encontrada com zoom 16.
- Criadores: Marcos Vinicius recebeu RGM `33712816` e link clicável para `https://github.com/Marcos-Ara`.
- Scanner: preview maior, preenchimento da câmera no quadro, moldura útil maior e entrada ao vivo aumentada de 640 para 768 px.
- Modelo local permanece `assets/models/ecoscan_yoloe26n_w8a32.tflite`.
- Release continua com minificação/shrink desativados conforme correção do crash anterior.

## Banco de dados

Para uma base Supabase que já recebeu o SQL anterior, execute apenas:

`supabase/migrations/202610020001_fato_scan.sql`

No projeto novo/do zero, `supabase/ECOSCAN_SUPABASE_NOVO.sql` já contém tudo.

O Flutter usa apenas a chave pública. Não coloque `service_role` no aplicativo.

## Validação final no Windows

Este ambiente não possui Flutter SDK para executar a compilação. No PC do projeto rode:

```powershell
flutter clean
flutter pub get
flutter analyze
flutter test
flutter build apk --release --dart-define-from-file=config/mobile.json
```

O APK final fica em `build/app/outputs/flutter-apk/app-release.apk`.
