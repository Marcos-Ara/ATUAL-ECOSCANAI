# Validação da base EcoScan 3.4.8 — análise da foto e diagnóstico Supabase

## Objetivo desta entrega

Esta versão mantém o scanner e adiciona um formulário para relatar identificações erradas ou objetos não encontrados. As amostras deixam de ser coletadas automaticamente e não há limite fixo de 30 itens.

- As imagens e correções ficam no aparelho até a pessoa confirmar o envio em Configurações.
- O envio requer uma conta conectada ao Supabase e usa o bucket privado `ecoscan-training`.
- Para uma base Supabase já existente, execute `supabase/migrations/202610080001_learning_reports.sql` antes do primeiro envio.
- As correções entram como relatos pendentes de revisão. Elas não treinam nem atualizam o YOLO-E automaticamente.
- A migração SQL agora também cria (ou repara) o bucket privado `ecoscan-training`, que faltava no erro 404 mostrado.
- Tocar novamente na aba Scan ou no botão de retorno limpa a foto e abre o scanner ao vivo. Se uma operação estiver em andamento, o retorno é aplicado assim que ela terminar.
- **Fotografar** mostra progresso enquanto a foto capturada é analisada e abre um resumo com imagem, material e destino; ao continuar, a leitura ao vivo volta.
- A análise informa especificamente quando o bucket `ecoscan-training` não existe no projeto Supabase conectado.
- A seção de amostras aparece como disponível e continua sem limite local; o envio só acontece depois do consentimento explícito.
- O fluxo não altera os pesos do modelo YOLO-E: uma correção enviada entra para revisão humana.

## Scanner Android

O Android agora usa `YOLOView` (`ultralytics_yolo 0.6.15`) para inferência diretamente no vídeo.

Fluxo ao vivo:

`câmera → YOLOView → onResult → seleção do objeto → estabilização → catálogo local → material/lixeira`

Não existe mais, no Android, o loop de `Timer + takePicture + JPG` para cada leitura ao vivo.

Configuração inicial:

- modelo: `assets/models/ecoscan_yoloe26n_w8a32.tflite`
- câmera: traseira, 720p
- confidence do YOLOView: 0.25
- IoU: 0.50
- GPU: habilitada
- estabilização: 4 leituras / 2 confirmações
- seleção: moldura ampla e tolerante a objeto parcialmente enquadrado
- diagnóstico visível: FPS, tempo de inferência, objeto, confiança e classe

A foto/galeria continua usando inferência de imagem única. Ao fotografar no modo ao vivo, se a análise da foto ficar inconclusiva, uma detecção YOLO-E recente (até 2 segundos) pode completar o resultado para o mesmo frame.

## Dados locais preservados

- 57 classes YOLO-E
- 190 objetos
- 261 sinônimos
- 9 variações
- 128 EcoPontos GeoSampa
- modelo TFLite local

O resultado local agora preserva também `objectId`, `variantId`, `detectionLabel` e `classIndex` quando disponíveis.

## Supabase e consentimento

`config/mobile.json` contém:

- `ECOSCAN_USE_SUPABASE_MODEL=false`
- `ECOSCAN_USE_SUPABASE_CATALOG=false`
- `ECOSCAN_USE_SUPABASE_ECOPOINTS=false`
- `ECOSCAN_SYNC_SUPABASE_HISTORY=false`

Essas opções controlam modelo, catálogo, EcoPontos e histórico; o envio de correções usa o bucket e a tabela de treinamento descritos acima.

## Verificações desta entrega

- estrutura YAML/JSON/XML: OK
- imports Dart relativos: OK
- balanceamento léxico dos arquivos Dart: OK
- modelo TFLite presente: OK
- metadata embutida do modelo: `task=detect`, `head=YOLOEDetect`, `imgsz=640x640`, **57 classes**: OK
- SHA-256 do modelo: `f7d4200deee29f48f2d7d14d1ba011d6c21b99a2dff02bae039234f0c7e43abf`
- catálogo local presente: OK
- contagens locais: 57 / 190 / 261 / 9 / 128: OK
- `ultralytics_yolo` travado em 0.6.15 no lockfile: OK
- API usada pelo wrapper conferida contra a documentação oficial de `YOLOView`, `YOLOResult`, `YOLOPerformanceMetrics` e `YOLOViewController`: OK
- teste de persistência dos campos da correção: adicionado
- teste manual necessário: criar o bucket/tabela com a migração e enviar uma amostra com consentimento para confirmar que a linha aparece como `pending`
- teste de ciclo do scanner cobre o indicador de progresso e o resumo da foto; executar com `flutter test` no Windows após extrair esta versão
- imports Dart relativos e JSON de configuração/Hosting: OK
- `node --test test/web_bridges_test.cjs`: **13/13 testes passaram**
- os sete avisos apresentados no último `flutter analyze` foram tratados: dropdown atualizado para `initialValue`, assertions/operadores redundantes removidos, acesso ao contexto protegido entre operações assíncronas e fluxo do `finally` reestruturado

Este ambiente não possui Flutter SDK/Android SDK, então `flutter analyze`, `flutter test` e a compilação APK/Web não puderam ser repetidos após esses ajustes. Rode-os no Windows do projeto antes de publicar.

## Configurar e revisar no Supabase

Abra `supabase/migrations/202610080001_learning_reports.sql` e execute o arquivo inteiro no SQL Editor do projeto Supabase. Isso cria ou atualiza a tabela, o bucket privado e as políticas necessárias para uploads dos próprios usuários. Para revisar correções e aprovar ou rejeitar amostras, siga `supabase/REVISAR_AMOSTRAS.md`.

## Validação final no Windows

No diretório do projeto:

```powershell
Set-Location 'C:\Users\ANHANGUERA\Desktop\ECOSCAN AI AHH\ATUAL-ECOSCANAI'
where.exe flutter
$env:FLUTTER_ROOT = 'C:\Users\ANHANGUERA\develop\flutter'
$flutter = Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat'
& $flutter clean
& $flutter pub get
& $flutter analyze
& $flutter test
node --test test/web_bridges_test.cjs
& $flutter build apk --release --dart-define-from-file=config/mobile.json
& $flutter build web --release --no-web-resources-cdn --dart-define-from-file=config/mobile.json
```

O Flutter correto no seu PC deve continuar apontando para:

`C:\Users\ANHANGUERA\develop\flutter\bin\flutter`

O APK fica em:

`build\app\outputs\flutter-apk\app-release.apk`

## Teste no Moto G35

1. Abrir Scanner: câmera deve abrir sem crash.
2. Esperar `YOLO-E ● ATIVO`.
3. Conferir se FPS e inferência aparecem.
4. Celular: deve estabilizar após duas confirmações.
5. Teclado: testar a classe do YOLO-E.
6. Garrafa plástica: Plástico / Vermelha.
7. Garrafa de vidro: Vidro / Verde.
8. Lata de alumínio: Metal / Amarela.
9. Eletrônico: Coleta especial.
10. Testar Foto e Galeria.
11. Salvar: deve permanecer no histórico local.
12. Fechar/abrir app: histórico deve permanecer.

Depois dos testes locais, faça o deploy web pelo Firebase Hosting. A integração com n8n, revisão automatizada por segunda IA e reexportação de pesos do YOLO-E são etapas futuras; ainda não estão conectadas nesta base.
