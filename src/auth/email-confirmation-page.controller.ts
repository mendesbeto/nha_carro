import { Controller, Get, Header } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';

@Controller('confirm-email')
export class EmailConfirmationPageController {
  @Get()
  @Header('Content-Type', 'text/html; charset=utf-8')
  @Header('Cache-Control', 'no-store, max-age=0')
  @Header('Referrer-Policy', 'no-referrer')
  @Header('Content-Security-Policy', "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'")
  @Throttle({ default: { limit: 30, ttl: 60_000 } })
  page(): string {
    return `<!doctype html>
<html lang="pt">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="referrer" content="no-referrer">
<title>NhaCarro — Confirmação de e-mail</title>
<style>
body{font-family:Arial,sans-serif;background:#f8faf9;margin:0;padding:32px;color:#1f2937}
main{max-width:480px;margin:40px auto;background:#fff;padding:28px;border-radius:16px;box-shadow:0 4px 20px rgba(0,0,0,.08)}
h1{font-size:26px}p{line-height:1.5;color:#4b5563}
a{display:inline-block;margin-top:18px;padding:13px 20px;border-radius:10px;background:#0b8f62;color:#fff;text-decoration:none;font-weight:700}
</style>
</head>
<body><main><h1 id="title">A verificar a confirmação...</h1><p id="message">Aguarde um instante.</p><a id="app-link" href="https://mendesbeto.github.io/nha_carro/" hidden>Voltar ao NhaCarro</a></main>
<script>
(() => {
  const params = new URLSearchParams(window.location.hash.replace(/^#/, ''));
  const type = params.get('type');
  const token = params.get('access_token');
  const title = document.getElementById('title');
  const message = document.getElementById('message');
  const link = document.getElementById('app-link');
  window.history.replaceState({}, document.title, window.location.pathname);
  if (type === 'signup' && token) {
    title.textContent = 'E-mail confirmado!';
    message.textContent = 'O seu endereço foi confirmado com sucesso. Já pode voltar ao NhaCarro e iniciar sessão.';
    link.hidden = false;
  } else {
    title.textContent = 'Não foi possível confirmar';
    message.textContent = 'O link é inválido, expirou ou já foi utilizado. Solicite um novo link de confirmação.';
  }
})();
</script></body></html>`;
  }
}
