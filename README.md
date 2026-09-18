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

O cadastro recebe o e-mail do Flutter e mantém as credenciais na tabela
`auth_credentials`; o campo `email` dessa tabela é a fonte oficial do
e-mail retornado pela API. O campo legado `usuarios.telefone` continua sendo
preenchido com o e-mail por compatibilidade com o schema inicial.

A tabela `auth_credentials` guarda o hash bcrypt da senha. As rotas
protegidas usam `Authorization: Bearer <access_token>`, e a identidade do
passageiro em uma solicitação de corrida vem do token, não do cliente.

A solicitação de corrida sempre retorna uma tarifa estimada; sem coordenadas
(o caso atual do Flutter) nenhuma corrida é inserida.

## Recuperação de palavra-passe

O backend disponibiliza recuperação de palavra-passe por token de uso único, com validade de 30 minutos. Configure no ambiente de produção:

- `RESEND_API_KEY`: chave da API do Resend.
- `EMAIL_FROM`: remetente verificado no Resend.
- `PASSWORD_RESET_URL`: URL HTTPS confiável da página `/reset-password`.

Após uma recuperação bem-sucedida, a versão da sessão do utilizador é incrementada e os refresh tokens existentes são revogados. Os access tokens emitidos antes da recuperação deixam de ser aceites pelo guard.
