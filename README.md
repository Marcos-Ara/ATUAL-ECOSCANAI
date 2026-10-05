# EcoScan AI — Flutter + Supabase 3.4.3

Base completa do projeto enviado, com YOLOE-26n LiteRT incluído para Android, 57 prompts de objetos, scanner ao vivo ajustado, catálogo offline atualizado e os 128 EcoPontos oficiais GeoSampa.

## Começar no Windows / VS Code

1. Extraia o ZIP e abra **ATUAL ECOSCANAI**, a pasta que contém `pubspec.yaml`.
2. Rode no terminal:

```powershell
flutter pub get
flutter run -d chrome --web-hostname localhost --web-port 7357
```

`config/mobile.json` já está incluído. Também funciona o comando anterior:

```powershell
flutter run -d chrome --web-hostname localhost --web-port 7357 --dart-define-from-file=config/mobile.json
```

O projeto vem configurado para `https://kekcfxoiyufskltnzlie.supabase.co`, com a publishable key fornecida. Não há referência ao projeto Supabase antigo na configuração ou nos guias. Firebase não é utilizado.

Para testar o mapa antes de configurar login, clique em **Continuar sem conta**, depois **Mapa**.

## Comportamento dos EcoPontos

- **Mapa:** todos os 128 pontos oficiais de São Paulo continuam carregados. Quando a localização do usuário é encontrada, o mapa centraliza automaticamente nela com zoom 16; o botão **Ver todos** continua disponível para mostrar o catálogo completo.
- O botão **Ver todos** ajusta o enquadramento ao catálogo completo.
- **Barra inferior:** até 10 pontos mais próximos, ordenados por distância, dentro de 5, 10 ou 25 km. O raio inicial é 5 km.
- Com localização autorizada, a distância é relativa ao usuário, mesmo se ele mover o mapa.
- Sem localização, a lista usa o centro do mapa e muda quando o mapa se move. A interface identifica essa referência.
- Texto e material filtram a barra; não removem os marcadores do mapa.
- Nenhum resultado dentro do raio mostra uma mensagem para ampliar a distância ou limpar a busca. O app não inventa destinos para materiais não informados pela fonte.
- Nome, endereço, distrito, subprefeitura, horário e materiais recebidos vêm do GeoSampa. Restos de poda não são tratados como autorização para resíduos alimentares ou compostagem.
- O arquivo original usa **SIRGAS 2000 / UTM 23S (EPSG:31983)**. As coordenadas foram convertidas para **WGS84 (longitude/latitude)** antes da inclusão. Ex.: Bresser = `-23.54340338, -46.60646234`.
- Os pontos são carregados de `assets/data/ecopoints_geosampa.geojson`. A abertura do mapa não depende de GPS, API key, WFS, Edge Function ou importação no Supabase.
- Nesta fase o catálogo remoto está desligado; o botão atualizar mantém/recarrega a cópia local. A sincronização com `public.ecopoints` será reativada somente depois da validação do scanner e da criação do banco definitivo.
- O renderizador Web CanvasKit é carregado dos arquivos da própria publicação.
- A imagem do mapa (ruas/satélite) e as rotas externas continuam exigindo internet. O catálogo de pontos está dentro do app.

**Cobertura:** o arquivo enviado contém pontos do município de São Paulo. Estar em outra cidade não impede carregar/ver esses 128 pontos, mas não cria um catálogo de ecopontos de outros municípios.

## Supabase nesta fase de validação

**Não execute os SQLs do banco ainda.** Nesta 3.4.3, o Supabase fica ativo apenas para **Auth** (cadastro, login, Google, confirmação e recuperação). O scanner, catálogo, EcoPontos, histórico e modelo usam a base local enquanto validamos o YOLO-E no Android.

Os arquivos SQL e migrations continuam preservados no projeto para a próxima etapa, mas `config/mobile.json` deixa desativados:

- `ECOSCAN_USE_SUPABASE_MODEL`
- `ECOSCAN_USE_SUPABASE_CATALOG`
- `ECOSCAN_USE_SUPABASE_ECOPOINTS`
- `ECOSCAN_SYNC_SUPABASE_HISTORY`

Depois que os testes do scanner passarem no aparelho, o schema definitivo será montado a partir do Supabase vazio e os dados locais serão importados automaticamente. Isso evita misturar erro de câmera/modelo com erro de banco.

## Login e Google no projeto novo

E-mail, senha, cadastro, recuperação e Google usam exclusivamente Supabase Auth.

Configure **Authentication → URL Configuration**:

- Site URL de desenvolvimento: `http://localhost:7357`.
- Redirect permitido para Web: `http://localhost:7357`.
- Redirect para Android/iOS: `ecoscan://login-callback/`.
- O projeto usa o manipulador de links do `supabase_flutter`/`app_links`; por isso o deep linking padrão do Flutter fica desativado no Android/iOS para evitar conflito.
- Quando publicar a Web, inclua a URL real da publicação nas configurações.

Habilite o provedor **Google** no Supabase e preencha Client ID e Client Secret do Google Cloud. No Google Cloud, o callback autorizado do novo projeto é:

`https://kekcfxoiyufskltnzlie.supabase.co/auth/v1/callback`

O Client ID atualizado é `980630728564-c2uvaqelhr3ekmdn90mc9rmrtrkaccqh.apps.googleusercontent.com`. As origens JavaScript autorizadas são `http://localhost:7357` e `https://ecoscan-ai-e961f.web.app`. No Google Cloud, mantenha também o callback acima como URI de redirecionamento autorizado. Use o Client Secret atual do arquivo JSON do Google Cloud para atualizar o campo **Client Secret** do provedor Google no Supabase.

Não coloque Client Secret ou service-role no Flutter, em `config/mobile.json` ou neste ZIP. O segredo do Google é usado pelo Supabase no servidor e deve permanecer somente nas configurações do provedor. Contas do projeto antigo não passam automaticamente para o projeto novo: cadastre novamente uma conta para testar. O modo visitante não cria usuário remoto.

## Aba de download do APK

Na versão Web, a navegação inclui a aba **Baixar** com um botão de download do APK. Para publicar uma nova versão, cole o link HTTPS direto para o arquivo no campo `ECOSCAN_APK_DOWNLOAD_URL` de `config/mobile.json` e publique novamente o site. Enquanto o campo estiver vazio, o botão aparece como **APK em breve** e fica desativado. O link não contém credenciais e pode ser alterado a cada lançamento.

## Scanner e dados locais

**Android:** o scan ao vivo usa `YOLOView` do pacote oficial `ultralytics_yolo 0.6.15`, com o modelo local `assets/models/ecoscan_yoloe26n_w8a32.tflite`. A câmera envia frames diretamente ao runtime nativo; não existe mais o ciclo `Timer → takePicture() → JPG → predict()` no Android. O callback `onResult` entrega as detecções em tempo real e o EcoScan faz seleção, estabilização e objeto → material → lixeira localmente.

Configuração inicial do ao vivo:

- confiança de entrada do YOLOView: **0,25**;
- IoU: **0,50**;
- GPU habilitada com fallback do runtime quando necessário;
- câmera traseira em **720p**;
- moldura útil ampla, sem exigir alinhamento milimétrico;
- estabilizador: janela de 4 leituras, **2 confirmações** antes de assumir o objeto;
- diagnóstico temporário na tela: **YOLO-E ativo, FPS, inferência, objeto/confiança e índice de classe**.

A confiança 0,25 apenas permite que um candidato entre no pipeline. O catálogo ainda aplica o piso de confiança específico de cada prompt (em geral 0,35), além de estabilidade e mapeamento local, para reduzir falso positivo. O scan ao vivo não faz RPC nem consulta Supabase por frame.

**Foto/Galeria:** continuam separadas do vídeo. Uma foto usa o caminho de inferência única (`YOLO.predict`) e depois a mesma resolução de objeto → material → lixeira. Ao fotografar a partir do scanner ao vivo, o frame é capturado pelo próprio `YOLOView`; o stream é pausado enquanto a análise única roda, evitando duas câmeras concorrentes.

**Web:** continua usando a ponte Web existente (COCO-SSD/MobileNet) e não importa `YOLOView`, preservando o build Web. **iOS:** continua no fluxo anterior por enquanto, pois esta base inclui o modelo LiteRT/TFLite do Android; o equivalente Core ML será tratado separadamente.

Os 57 prompts YOLO-E continuam ligados ao catálogo local, que possui 190 objetos, 261 sinônimos e 9 variações. O resultado agora também pode carregar `objectId`, `variantId`, `detectionLabel` e `classIndex`, preparando o futuro `FATO_SCAN` sem depender do banco nesta fase.

Os EcoPontos continuam usando os 128 registros do GeoSampa local. O histórico continua local nesta fase. Supabase continua somente no login.

## Validar e gerar APK de teste

```powershell
flutter analyze
flutter test
node --test test/web_bridges_test.cjs
flutter build web --release --no-web-resources-cdn --dart-define-from-file=config/mobile.json
flutter build apk --release --dart-define-from-file=config/mobile.json
```

O APK de teste fica em `build/app/outputs/flutter-apk/app-release.apk`. Compilar Android requer Android SDK e JDK configurados. A geração de APK não foi realizada nesta entrega.

Para executar o roteiro completo com Flutter:

```powershell
.\tool\verify_base.ps1
.\tool\verify_base.ps1 -BuildReleaseApk
```

## Atualizar a exportação GeoSampa no futuro

```powershell
python -m pip install pyproj
python tool/import_geosampa.py "C:\caminho\geoportal_ecoponto.geojson"
```

O script converte/valida o GeoJSON e atualiza os arquivos locais/SQL preparados. Enquanto o banco remoto estiver desligado, apenas reconstrua o app; a aplicação do SQL no Supabase fica para a etapa posterior. Não há sincronização WFS periódica automática nesta versão.
