# Modelo YOLOE Android incluído

`ecoscan_yoloe26n_w8a32.tflite`: detector real exportado em 30/09/2026 a partir do checkpoint oficial YOLOE-26n, com 57 prompts EcoScan. Quantização w8a32: pesos int8 e entrada/ativações float32. Entrada `[1,3,640,640]`, saída `[1,61,8400]`, metadata com labels na ordem correta. O runtime `ultralytics_yolo 0.6.15` aceita esse layout e lê os labels do metadata.

`model_manifest.json`: hash, tamanho, classes e resultado da inferência de fumaça no PC. Isso verifica a execução e o contrato; não mede precisão nem substitui o teste no Android.

O app Android tenta uma release Supabase com login, depois este asset, depois YOLO genérico/ML Kit. iOS precisa de Core ML; Web usa o scanner JavaScript existente. Instruções completas em `YOLOE_ATIVACAO.md` na raiz.

Modelo pré-treinado com prompts fixados, sem treinamento supervisionado EcoScan. Pesos/runtime Ultralytics: AGPL-3.0 ou Enterprise. Consulte a licença incluída e https://ultralytics.com/license antes de redistribuir.
