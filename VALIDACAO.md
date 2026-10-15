# Revisão desta base

## Pubspec e versão

- O `pubspec.yaml` usa Dart `>=3.12.0 <4.0.0`, compatível com o Dart 3.13.3 informado no ambiente de build.
- As dependências usadas nos imports do app e dos testes estão declaradas no `pubspec.yaml`.
- Os assets declarados existem na base: catálogo, GeoJSON, fontes e modelo YOLO.
- A versão foi incrementada de `3.4.9+28` para `3.4.10+29`, gerando um `versionCode` Android maior para o próximo APK.
- O `flutter pub get` enviado pelo usuário concluiu com sucesso. As notificações sobre pacotes mais novos são informativas.

## O que foi revisado

- Tabelas, campos, funções, políticas e visões finais do banco usam nomes em português.
- As chamadas do app e das ferramentas de amostras/modelos apontam para os nomes finais.
- A migração relaciona objetos, variantes, materiais, EcoPontos, leituras, pontos, conquistas e amostras.
- As políticas separam dados por conta e mantêm fotos/modelos em buckets privados.
- A resolução remota recusa rótulos ambíguos sem uma variante específica.
- O guia descreve o que sincroniza, o que requer revisão humana e o que não é automático.

## Limite desta conferência

Esta revisão inclui conferência estática do YAML, imports, assets e arquivos do banco. O SQL ainda precisa ser executado no projeto Supabase correto para confirmar o estado remoto. O SDK Flutter não está disponível neste ambiente, então não foi possível executar `flutter analyze`, os testes nem as compilações nesta cópia atualizada. Os resultados de análise/teste colados antes vieram da pasta antiga, antes de receber as correções incluídas nesta base.

## Próximos passos no seu computador

1. Extraia a base atualizada e abra no terminal a pasta que contém `pubspec.yaml`.
2. Siga `supabase/INSTALAR_BANCO_DO_ZERO.md` e execute o SQL consolidado uma única vez no projeto Supabase vazio.
3. Se o SQL terminar sem erros, gere o APK e a Web com `config/mobile.json`.
4. Faça login, salve uma leitura, abra o histórico em outro aparelho e confirme que a leitura sincronizou. Apague uma leitura e confirme que a exclusão também sincroniza.
5. Altere uma preferência, feche/abra o app e confira se ela volta da conta.
6. Envie uma correção só depois de aceitar o consentimento; confirme em `amostras_treinamento` que a situação inicial é `pendente` e confira a imagem em `Storage → ecoscan-training`.

Para compilar no PowerShell, ajuste o caminho do Flutter ao seu computador:

```powershell
$env:FLUTTER_ROOT = 'C:\Users\ANHANGUERA\develop\flutter'
$flutter = Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat'
& $flutter pub get
& $flutter analyze
& $flutter build apk --release --dart-define-from-file=config/mobile.json
& $flutter build web --release --no-web-resources-cdn --dart-define-from-file=config/mobile.json
```

Publique o site com `firebase.cmd deploy --only hosting` a partir da raiz do projeto, depois da compilação Web.
