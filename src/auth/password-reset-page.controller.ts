import {
  Body,
  Controller,
  Get,
  Header,
  HttpCode,
  Post,
  Query,
} from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { PasswordResetService } from './password-reset.service';

@Controller('reset-password')
export class PasswordResetPageController {
  constructor(private readonly passwordResetService: PasswordResetService) {}

  @Get()
  @Header('Content-Type', 'text/html; charset=utf-8')
  @Throttle({ default: { limit: 30, ttl: 60_000 } })
  page(@Query('token') token?: string): string {
    if (token) {
      return this.renderPage(
        'Redefinir palavra-passe',
        \`<form method="post" action="/reset-password">
          <input type="hidden" name="token" value="\${this.escape(token)}">
          \${this.formFields()}
        </form>\`,
      );
    }

    return this.renderPage(
      'Redefinir palavra-passe',
      \`<div id="recovery-form">
        <p>Defina uma nova palavra-passe para a sua conta NhaCarro.</p>
        <form method="post" action="/reset-password" id="password-reset-form">
          <input type="hidden" name="token" id="recovery-token">
          \${this.formFields()}
        </form>
      </div>
      <script src="/reset-password/recovery.js" defer></script>\`,
    );
  }

  @Get('recovery.js')
  @Header('Content-Type', 'application/javascript; charset=utf-8')
  @Throttle({ default: { limit: 60, ttl: 60_000 } })
  recoveryScript(): string {
    return \`(() => {
  const form = document.getElementById('password-reset-form');
  const tokenInput = document.getElementById('recovery-token');
  const hash = window.location.hash.replace(/^#/, '');
  const params = new URLSearchParams(hash);
  const accessToken = params.get('access_token');
  if (!form || !tokenInput || !accessToken) {
    const box = document.getElementById('recovery-form');
    if (box) box.innerHTML = '<p>O link de recuperação está incompleto, inválido ou expirou.</p>';
    return;
  }
  tokenInput.value = accessToken;
  window.history.replaceState({}, document.title, window.location.pathname);
})();\`;
  }

  @Post()
  @HttpCode(200)
  @Header('Content-Type', 'text/html; charset=utf-8')
  @Throttle({ default: { limit: 5, ttl: 60_000 } })
  async reset(
    @Body()
    body: {
      token?: string;
      password?: string;
      passwordConfirmation?: string;
    },
  ): Promise<string> {
    if (!body.token || !body.password || !body.passwordConfirmation) {
      return this.renderPage(
        'Dados incompletos',
        '<p>Preencha todos os campos e tente novamente.</p>',
      );
    }

    try {
      await this.passwordResetService.resetWithAccessToken(
        body.token,
        body.password,
        body.passwordConfirmation,
      );
      return this.renderPage(
        'Palavra-passe alterada',
        '<p>A sua palavra-passe foi alterada com sucesso.</p><p>Já pode voltar à aplicação e iniciar sessão.</p>',
      );
    } catch (_) {
      return this.renderPage(
        'Não foi possível alterar a palavra-passe',
        '<p>O link de recuperação é inválido, expirou ou já foi utilizado.</p>',
      );
    }
  }

  private formFields(): string {
    return \`<label for="password">Nova palavra-passe</label>
    <input id="password" name="password" type="password" minlength="8" maxlength="128" required autocomplete="new-password">
    <label for="passwordConfirmation">Confirmar palavra-passe</label>
    <input id="passwordConfirmation" name="passwordConfirmation" type="password" minlength="8" maxlength="128" required autocomplete="new-password">
    <button type="submit">Alterar palavra-passe</button>
    <p>A palavra-passe deve ter pelo menos 8 caracteres.</p>\`;
  }

  private renderPage(title: string, content: string): string {
    return \`<!doctype html>
<html lang="pt">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="referrer" content="no-referrer">
<title>NhaCarro — \${this.escape(title)}</title>
<style>
body{font-family:Arial,sans-serif;background:#f8faf9;margin:0;padding:32px;color:#1f2937}
main{max-width:480px;margin:40px auto;background:#fff;padding:28px;border-radius:16px;box-shadow:0 4px 20px rgba(0,0,0,.08)}
h1{font-size:26px}label{display:block;margin:18px 0 6px;font-weight:600}
input{width:100%;box-sizing:border-box;padding:12px;border:1px solid #d1d5db;border-radius:10px}
button{margin-top:22px;width:100%;padding:13px;border:0;border-radius:10px;background:#0b8f62;color:#fff;font-weight:700;cursor:pointer}
p{line-height:1.5;color:#4b5563}
</style>
</head>
<body><main><h1>\${this.escape(title)}</h1>\${content}</main></body>
</html>\`;
  }

  private escape(value: string): string {
    return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
  }
}
