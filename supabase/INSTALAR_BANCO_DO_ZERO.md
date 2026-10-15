# Banco EcoScan no Supabase — instalação inicial

## Antes de começar

Esta instalação foi preparada para o projeto Supabase do EcoScan e parte de um banco sem tabelas próprias do app. O arquivo único `ECOSCAN_SUPABASE_NOVO.sql` reúne, em ordem, as migrações de `supabase/migrations/` e inclui os dados locais atuais do catálogo e dos EcoPontos.

Execute **uma única vez** o arquivo agregado no SQL Editor do projeto Supabase. Não execute o arquivo agregado e depois repita cada migração individual. Se o banco já tiver recebido alguma migração, pare e confira `supabase/migrations/` com o histórico antes de reaplicar os seeds.

Como esta primeira instalação é feita pelo SQL Editor, ela não preenche o histórico local do Supabase CLI. Continue aplicando futuras migrações novas pelo SQL Editor até sincronizar esse histórico; não rode `supabase db push` às cegas neste projeto.

## O que fica automático

- O Supabase Auth cria e mantém `profiles` quando uma pessoa cria conta, muda nome ou e-mail.
- Análises salvas sincronizam ao entrar na conta e ao salvar uma nova leitura. Se ficar sem conexão, o histórico local continua salvo e a sincronização tenta novamente quando o app voltar ao primeiro plano.
- Ao entrar em outro aparelho com a mesma conta, o app combina as leituras da nuvem com as locais; exclusões também são propagadas e não reaparecem quando um aparelho volta do modo offline. As fotos continuam no aparelho; imagens de amostras só são enviadas pelo fluxo separado de consentimento.
- O histórico na nuvem não envia latitude/longitude. Esses dados permanecem locais.
- O app consulta os EcoPontos no Supabase e usa a cópia embarcada/cache offline. Para materiais, o Supabase é consultado como fallback quando o catálogo embarcado não reconhece um rótulo; alterar uma classificação já conhecida no banco ainda exige atualizar o snapshot local em uma nova versão do app.
- `ecoscan_user_stats` calcula contagens e EcoPontos a partir das leituras da conta; a view respeita a RLS de `fato_scan`.
- Enviar correções e imagens para treinamento continua exigindo consentimento explícito. Isso cria uma amostra pendente para revisão; não treina nem troca o modelo automaticamente.

## Passos no painel

1. Abra o projeto Supabase configurado no EcoScan.
2. Entre em **SQL Editor** e crie uma consulta nova.
3. Abra `supabase/ECOSCAN_SUPABASE_NOVO.sql`, copie o conteúdo completo e execute.
4. Confira as contagens exibidas ao final: objetos, EcoPontos ativos, prompt YOLO-E e aliases. O arquivo também testa a resolução de uma embalagem ambígua e uma pilha.
5. Só depois de a consulta terminar sem erro, gere e publique novamente o APK/Web com `config/mobile.json`.

Se o painel acusar erro, não continue para o próximo passo: copie a mensagem completa do erro e confira se o SQL foi executado no projeto correto.

## Atualizações futuras do catálogo

Os dados iniciais são importados dos arquivos locais versionados. Para atualizar o catálogo ou EcoPontos, primeiro atualize os arquivos de dados e a migração de seed correspondente; depois aplique somente a migração nova. O app buscará o snapshot de EcoPontos do banco na próxima abertura do mapa e consultará o catálogo remoto quando a resolução local não reconhecer o objeto.

Não há coleta agendada direta do GeoSampa nesta fase. Uma atualização automática da fonte externa exige uma URL/API estável e um processo de importação agendado; editar dados no Supabase já passa a refletir no app sem novo APK.

## Limites desta primeira etapa

Histórico, perfil Auth, catálogo, EcoPontos e estatísticas derivadas ficam preparados. Foto de perfil, preferências visuais e exploração do mapa continuam locais. Amostras de treinamento ficam privadas e dependem do consentimento existente. A atualização automática dos pesos YOLO-E não está habilitada.
