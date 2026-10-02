# Validação da base EcoScan 3.4.3 — scanner YOLO-E ao vivo

## Objetivo desta entrega

Esta versão mexe somente no necessário para validar o scanner antes de criar o banco definitivo no Supabase.

- Supabase continua ativo para **Auth**.
- Modelo, catálogo, EcoPontos e histórico remoto ficam **desativados por padrão**.
- O SQL existente foi preservado, mas **não deve ser executado nesta fase**.

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

A foto/galeria continua usando inferência de imagem única. Ao tirar uma foto a partir do vídeo, o frame é capturado pelo próprio `YOLOView` e o stream é pausado durante a análise única.

## Dados locais preservados

- 57 classes YOLO-E
- 190 objetos
- 261 sinônimos
- 9 variações
- 128 EcoPontos GeoSampa
- modelo TFLite local

O resultado local agora preserva também `objectId`, `variantId`, `detectionLabel` e `classIndex` quando disponíveis.

## Supabase temporariamente desligado fora do Auth

`config/mobile.json` contém:

- `ECOSCAN_USE_SUPABASE_MODEL=false`
- `ECOSCAN_USE_SUPABASE_CATALOG=false`
- `ECOSCAN_USE_SUPABASE_ECOPOINTS=false`
- `ECOSCAN_SYNC_SUPABASE_HISTORY=false`

Isso evita que tabela vazia, RPC ausente ou rede confundam o teste do scanner.

## Verificações executadas nesta entrega

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
- `node --test test/web_bridges_test.cjs`: **13/13 testes passaram**

Este ambiente não possui Flutter SDK/Android SDK, então `flutter analyze`, `flutter test` e a compilação APK precisam ser executados no Windows do projeto.

## Validação final no Windows

No diretório do projeto:

```powershell
where.exe flutter
flutter clean
flutter pub get
flutter analyze
flutter test
node --test test/web_bridges_test.cjs
flutter build apk --release --dart-define-from-file=config/mobile.json
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

Somente depois desses testes passarem partimos para o schema definitivo do Supabase.
