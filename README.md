# nhacarro

Aplicação Flutter e backend NestJS do NhaCarro.

## Backend

O backend fica na raiz deste projeto e expõe as rotas usadas pelo Flutter:

- `POST /api/auth/register`
- `POST /api/auth/login`
- `POST /api/auth/refresh`
- `POST /api/auth/logout`
- `POST /api/auth/request-password-reset`
- `POST /api/auth/reset-password`
- `POST /api/rides/request`
- `GET /api/health`

### Configuração local e Render

Configure no servidor:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY` — somente backend, nunca enviada ao Flutter.
- `SUPABASE_PUBLISHABLE_KEY` (ou `SUPABASE_ANON_KEY`) — usada apenas para operações de sessão do utilizador.

O backend mantém um cliente service-role isolado para operações administrativas e um novo cliente Supabase Auth isolado por operação para login/refresh/validação de tokens. Isso evita compartilhar uma sessão de utilizador entre requisições concorrentes.

Instale e compile com `npm install` e `npm run build`. Inicie com `npm start` (ou `npm run start:prod`).

As credenciais de palavra-passe ficam exclusivamente no Supabase Auth; o projeto não utiliza mais a tabela legada `auth_credentials`.

A identidade das rotas protegidas vem do JWT validado pelo Supabase Auth, e o perfil/estado da conta é verificado no banco.

## Recuperação de palavra-passe

Configure:

- `RESEND_API_KEY`
- `EMAIL_FROM`
- `PASSWORD_RESET_URL`

O link de recuperação usa Supabase Auth. Depois da alteração da palavra-passe, as sessões de refresh são revogadas.

A solicitação de recuperação mantém resposta genérica para não revelar se um e-mail está registrado.
