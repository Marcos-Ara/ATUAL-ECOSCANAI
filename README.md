# EcoScan AI — Flutter + Supabase 3.4.2

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
- O botão atualizar consulta o catálogo completo em `public.ecopoints` no novo Supabase, com paginação. Uma resposta remota não vazia substitui o catálogo; falhas preservam a cópia disponível.
- O renderizador Web CanvasKit é carregado dos arquivos da própria publicação.
- A imagem do mapa (ruas/satélite) e as rotas externas continuam exigindo internet. O catálogo de pontos está dentro do app.

**Cobertura:** o arquivo enviado contém pontos do município de São Paulo. Estar em outra cidade não impede carregar/ver esses 128 pontos, mas não cria um catálogo de ecopontos de outros municípios.

## Preparar o Supabase novo

O app já aponta para o projeto novo, mas os arquivos SQL não foram executados remotamente por esta entrega.

1. Abra o projeto `kekcfxoiyufskltnzlie` no Supabase.
2. Vá em **SQL Editor → New query**.
3. Abra `supabase/ECOSCAN_SUPABASE_NOVO.sql`, copie todo o conteúdo e execute.
4. O final mostra as verificações: **128 ecopontos**, **190 objetos** e a resolução de `garrafa pet`.

Esse arquivo cria:

- `profiles`, sincronizado automaticamente com nome e e-mail do Supabase Auth;
- `fato_scan`, que registra no banco cada análise salva por um usuário autenticado, com objeto, material, lixeira, confiança, detector, data e localização quando disponível;
- `ecopoints`, com coordenadas, metadados e índice PostGIS;
- `objects`, `object_variants`, `object_aliases` e RPC `find_ecoscan_object(p_alias)`;
- os objetos, variantes e aliases do catálogo fornecido, mais 57 entradas específicas de YOLOE;
- os 128 ecopontos convertidos;
- registro de modelos e amostras de treinamento da base 3.2;
- buckets privados `ecoscan-models` e `ecoscan-training` e políticas de acesso;
- RLS: catálogo público somente para leitura; perfis e amostras acessíveis ao proprietário. Upload/edição de modelos exige administração.

Não apaga schemas, tabelas ou usuários. A chave pública no Flutter não tem permissão para instalar o SQL. Use o SQL Editor autenticado como administrador. O arquivo completo é para o banco novo; não o aplique sobre uma estrutura antiga diferente.

Alternativamente, usuários do Supabase CLI podem aplicar as migrações ordenadas em `supabase/migrations/`.

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

Não coloque Client Secret ou service-role no Flutter. Contas do projeto antigo não passam automaticamente para o projeto novo: cadastre novamente uma conta para testar. O modo visitante não cria usuário remoto.

## Scanner e dados locais

**Android:** o arquivo `assets/models/ecoscan_yoloe26n_w8a32.tflite` é real, foi exportado e validado no PC. O modelo usa 57 classes fixadas por prompts no checkpoint oficial YOLOE-26n; não foi treinado com fotos do EcoScan. O app tenta primeiro uma release ativa do Supabase quando há login, depois o modelo incluído e por último o YOLO genérico/ML Kit se os anteriores falharem. O modelo incluído funciona também para visitante e não exige baixar pesos na primeira abertura.

**Web:** mantém COCO-SSD/MobileNet. O arquivo LiteRT incluído não é executado pelo navegador nesta versão. **iOS:** exige o equivalente Core ML publicado ou configurado; o arquivo Android não é um modelo iOS.

No Android, o scan ao vivo usa confiança 0,35, IoU 0,50, intervalo mínimo de 650 ms entre capturas, imagem de análise com até 768 px e estabilizador de 4 leituras com pelo menos 2 confirmações. A área visível da câmera foi ampliada e usa preenchimento do quadro para facilitar o enquadramento. Inferências não se sobrepõem.

A seleção ao vivo exige objeto dentro da moldura. YOLO confirmado determina os candidatos; ML Kit não substitui o label por um objeto do fundo durante estabilização. Quando o objeto desaparece, o resultado deixa de ser confirmado. Fotos usam o quadro inteiro e não aguardam duas leituras.

Os 57 prompts têm nomes e orientação no catálogo local. Papelão usa a categoria Papel. Pilhas, lâmpadas e óleo exigem orientação específica; recipiente genérico de alimento fica inconclusivo em vez de inventar um material. A foto não determina contaminação, conteúdo ou todas as características do resíduo. Longe de garantir acerto para qualquer objeto, esta base permite medir e melhorar o reconhecimento no celular.

Ao vivo: catálogo local, sem RPC por frame. Foto inconclusiva: pode consultar `find_ecoscan_object`. Não há confirmação manual obrigatória. O histórico visual continua no aparelho; quando um usuário autenticado salva uma análise, os metadados também são enviados para `public.fato_scan`. Se o envio falhar por falta de rede, os registros locais são tentados novamente na próxima entrada da conta. Amostras de treinamento continuam dependendo de consentimento explícito.

O botão Voltar do Android continua retornando das abas ao Início.

## Validar e gerar APK de teste

```powershell
flutter analyze
flutter test
node --test test/web_bridges_test.cjs
flutter build web --release --no-web-resources-cdn --dart-define-from-file=config/mobile.json
flutter build apk --debug --dart-define-from-file=config/mobile.json
```

O APK de teste fica em `build/app/outputs/flutter-apk/app-debug.apk`. Compilar Android requer Android SDK e JDK configurados. A geração de APK não foi realizada nesta entrega.

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

O script converte/valida o GeoJSON, atualiza o asset e recria o SQL de ecopontos e o SQL completo. Após uma nova exportação, reconstrua o app e reaplique o SQL correspondente no Supabase. Não há sincronização WFS periódica automática nesta versão.
