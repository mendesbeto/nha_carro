# nhacarro

Aplicação Flutter e backend NestJS do NhaCarro.

## Backend

O backend fica na raiz deste projeto e expõe as rotas usadas pelo Flutter:

- `POST /api/auth/register`
- `POST /api/auth/login`
- `POST /api/rides/request`
- `GET /api/health`

### Configuração local e Render

1. Execute o SQL `database/001_initial_schema.sql` e depois
   `database/002_auth_credentials.sql` no projeto Supabase.
2. Configure `SUPABASE_URL` e `SUPABASE_SERVICE_ROLE_KEY` no ambiente do
   servidor. A service role é usada apenas no backend e nunca é enviada ao
   Flutter.
3. Instale e compile com `npm install` e `npm run build`.
4. Inicie com `npm start` (ou `npm run start:prod`). O servidor escuta
   `PORT`, fornecida pelo Render, e usa `3001` localmente como padrão.

O cadastro recebe e-mail do Flutter e grava esse valor em
`usuarios.telefone` até que o schema tenha uma coluna de e-mail. A tabela
`auth_credentials` guarda somente o hash bcrypt da senha. A solicitação de
corrida sempre retorna uma tarifa estimada; sem coordenadas (o caso atual do
Flutter) nenhuma corrida é inserida. Para persistir uma corrida, envie também
`passengerId` e as quatro coordenadas.
