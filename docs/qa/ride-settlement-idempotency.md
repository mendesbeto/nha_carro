# QA: idempotência da conclusão de corrida

## Objetivo

Verificar que chamadas concorrentes e repetidas à RPC `complete_ride_and_settle_wallet(p_ride_id, p_actor_id)` não duplicam débito do passageiro, crédito do motorista nem dívida de comissão.

## Estado atual da evidência

- Os testes unitários em `src/wallet/wallet.service.spec.ts` validam a chamada à RPC e o mapeamento da resposta com mocks.
- A implementação SQL inspecionada bloqueia a corrida com `FOR UPDATE`, usa referências estáveis de transação e tem uma restrição única por `corrida_id` em `dividas_comissao_motorista`.
- Esses pontos estruturais são bons sinais, mas não substituem um teste de integração com duas sessões PostgreSQL reais.
- Não executar este teste contra dados de produção: a função pode concluir corridas e criar lançamentos reais.

## Matriz de teste isolado

Executar somente num banco de teste descartável que tenha as mesmas migrações, enums, funções auxiliares, triggers e constraints do Supabase.

1. **Dinheiro — duas chamadas simultâneas:** duas sessões chamam a RPC para a mesma corrida em andamento e com o mesmo motorista. Esperado: ambas retornam sem erro inesperado; corrida concluída; exatamente uma dívida para a corrida; nenhuma transação de carteira associada à liquidação em dinheiro.
2. **Dinheiro — repetição sequencial:** chamar novamente após a primeira chamada. Esperado: mesma dívida e mesmo estado, sem segunda dívida.
3. **Carteira — duas chamadas simultâneas:** usar corrida de teste paga pela carteira e saldo suficiente. Esperado: uma única transação de débito do passageiro e uma única de crédito do motorista, com referências estáveis `RIDE:<id>` e `RIDE:<id>:MOTORISTA`.
4. **Carteira — saldo insuficiente:** confirmar que a transação falha atomicamente e não deixa só o débito ou só o crédito aplicado.
5. **Autorização:** chamar com ator diferente do motorista atribuído. Esperado: rejeição e nenhuma alteração.
6. **Estados inválidos:** tentar liquidar corrida cancelada ou ainda não iniciada. Esperado: rejeição e nenhuma movimentação financeira.

## Critérios de aprovação

- Nenhuma duplicação de dívida ou transação.
- Nenhum saldo parcialmente alterado após erro.
- Repetição idempotente sem novos lançamentos.
- Autorização e transições de estado respeitadas.
- Evidência guardada com IDs de fixtures sintéticos, resultados das duas sessões e contagens antes/depois.

## Segurança operacional

Não use IDs de corridas reais, não faça UPDATE/INSERT diretamente no banco de produção e não marque dívidas como pagas sem confirmação de recebimento. O teste precisa de um banco isolado com schema e funções equivalentes; um mock Jest não comprova concorrência do PostgreSQL.
