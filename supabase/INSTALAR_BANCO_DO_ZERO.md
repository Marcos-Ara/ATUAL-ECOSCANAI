# Instalar o banco do EcoScan AI no Supabase

Este guia vale para um projeto Supabase novo, ainda sem tabelas do EcoScan. O arquivo `ECOSCAN_SUPABASE_NOVO.sql` junta as migrações na ordem correta, inclui o catálogo e os EcoPontos da base e termina com consultas de conferência.

> Execute a instalação consolidada **uma vez só** no SQL Editor. Não rode depois as migrações individuais. Se você já executou alguma versão anterior do SQL no projeto, pare e confira o banco antes de continuar: esta instalação do zero não deve ser repetida por cima.

## 1. Conferir o projeto correto

No painel Supabase, abra o projeto usado pelo app e confira se a URL do projeto termina em `kekcfxoiyufskltnzlie.supabase.co`. Ela deve ser a mesma configurada em `config/mobile.json`. Não cole nem compartilhe a chave privada `service_role`; o app usa somente a chave pública.

## 2. Rodar a estrutura completa

1. No painel, abra **SQL Editor** e escolha **New query**.
2. Abra `supabase/ECOSCAN_SUPABASE_NOVO.sql` dentro desta base atualizada.
3. Copie o arquivo inteiro, cole na consulta e clique em **Run**.
4. Espere a execução terminar. As consultas no final devem mostrar os totais de objetos, variantes, sinônimos, classes YOLO-E e EcoPontos GeoSampa, além de confirmar que o rótulo genérico ambíguo `bottle` não foi classificado automaticamente.

Se aparecer qualquer erro, não continue para o próximo passo. Copie a mensagem completa e confira em qual projeto a consulta foi aberta.

## 3. Atualizar o aplicativo

O banco final usa tabelas e colunas em português. Portanto, gere e publique a versão Web/APK com o código que acompanha esta mesma base; uma versão antiga do app ainda tentará chamar os nomes anteriores.

O app continua funcionando localmente se o Supabase estiver fora do ar. Ao autenticar, sincroniza o histórico, as exclusões e as preferências; o mapa consulta os EcoPontos; correções só sobem após consentimento. O catálogo embarcado continua sendo a primeira opção para reconhecer materiais, e a base remota serve como busca complementar.

## O que fica automático depois da instalação

- O Auth mantém `perfis` sincronizado com nome e e-mail da conta.
- Leituras salvas e exclusões do histórico sincronizam entre aparelhos autenticados.
- Preferências de tema, sons, avisos e mapa são carregadas da conta e sincronizadas quando mudam. A foto de perfil permanece local nesta etapa.
- O banco recalcula `eventos_pontos`, `conquistas_usuario` e `estatisticas_usuario` ao receber leituras/exclusões ou mudanças de progresso.
- O app atualiza o catálogo de EcoPontos e guarda cache local para uso offline.
- Amostras são enviadas para o bucket privado `ecoscan-training` somente quando a pessoa autoriza. Elas ficam pendentes para revisão.

## O que ainda exige uma pessoa

- Conferir e aprovar ou rejeitar amostras de treinamento.
- Exportar as amostras aprovadas, treinar e avaliar o modelo, e publicar uma versão com arquivo, tamanho e hash corretos.
- A opção `ECOSCAN_USE_SUPABASE_MODEL` continua desligada por padrão. O app não substitui os pesos YOLO só porque chegou uma correção.
- Uma atualização agendada automática do GeoSampa depende de uma fonte/API estável e de um processo externo de importação. Mudanças feitas diretamente no banco aparecem no app quando o catálogo é atualizado.

## Instalação futura

Como esta primeira instalação pelo SQL Editor não registra migrações no Supabase CLI, continue aplicando migrações novas pelo SQL Editor e confira o histórico antes de usar `supabase db push`. Para futuras alterações, aplique apenas a migração nova correspondente; não execute de novo o pacote de instalação inicial.
