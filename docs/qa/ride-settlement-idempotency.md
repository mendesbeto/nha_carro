# QA: idempotência da conclusão de corrida e dívida de comissão

## Objetivo
Validar que chamadas repetidas ou concorrentes à RPC `complete_ride_and_settle_wallet` não debitam o passageiro, não creditam o motorista nem criam dívida de comissão duplicada.

## Evidência já verificada
- Os testes unitários em `src/wallet/wallet.service.spec.ts` usam mocks e não demonstram concorrência real no PostgreSQL.
- A implementação SQL inspecionada bloqueia a corrida com `FOR UPDATE`, usa referências estáveis de transação e tem uma restrição única por `corrida_id` para dívidas.
- Ainda não foi executado um teste de integração concorrente. Não considerar a idempotência comprovada experimentalmente até esse teste passar.

## Preparação obrigatória
Executar apenas num banco descartável/isolado que tenha as mesmas migrações, enums, funções auxiliares, triggers e constraints do Supabase. Criar fixtures sintéticas de passageiro, motorista e corrida; registar saldos e contagens antes do teste. Usar duas ligações PostgreSQL independentes. **Não executar chamadas de teste contra corridas reais em produção**, porque a RPC pode concluir corridas e criar lançamentos financeiros.

## Cenários

### A. Dinheiro — concorrência
1. Criar corrida sintética em `EM_ANDAMENTO`, atribuída a motorista ativo, com pagamento `DINHEIRO` e comissão conhecida.
2. Invocar `public.complete_ride_and_settle_wallet(ride_id, driver_id)` em duas sessões quase simultaneamente.
3. Confirmar estado final `CONCLUIDA` e exatamente uma linha em `dividas_comissao_motorista` para essa corrida.
4. Confirmar que o valor e o motorista da dívida são corretos e que não surgiram transações de débito/crédito da liquidação por carteira.
5. Repetir a chamada sequencialmente; confirmar que não aparece nova dívida e que ID/estado permanecem consistentes.

### B. Carteira — concorrência
1. Criar corrida sintética paga por carteira, com saldo suficiente.
2. Registar os saldos e contagens de transações do passageiro e motorista.
3. Invocar a RPC em duas sessões quase simultaneamente.
4. Confirmar no máximo um débito do passageiro com referência `RIDE:<ride_id>` e um crédito do motorista com referência `RIDE:<ride_id>:MOTORISTA`.
5. Confirmar que os saldos refletem exatamente uma liquidação; repetir a chamada e garantir que não são criados novos movimentos.

### C. Atomicidade e autorização
- Saldo insuficiente: verificar que não fica apenas o débito ou apenas o crédito aplicado.
- Ator diferente do motorista atribuído: rejeição sem alteração de dados.
- Corrida cancelada ou ainda não iniciada: rejeição sem movimentos financeiros.

## Critérios de aprovação
- Uma única dívida por corrida em dinheiro.
- No máximo um débito do passageiro e um crédito do motorista por corrida paga por carteira.
- Chamadas repetidas não criam novos lançamentos.
- Nenhum saldo parcialmente alterado após erro.
- Regras de autorização e transição de estado respeitadas.

## Evidência a guardar
Guardar o commit testado, execução CI, IDs sintéticos, horários e resultados de ambas as sessões, e consultas/contagens antes e depois. Nunca usar IDs reais de clientes/motoristas nem marcar dívidas como pagas sem confirmação de recebimento.

**Estado:** plano de teste atualizado; teste concorrente real ainda não executado.