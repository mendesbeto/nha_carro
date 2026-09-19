import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

@Injectable()
export class EmailService {
  private readonly logger = new Logger(EmailService.name);

  constructor(private readonly config: ConfigService) {}

  async sendPasswordResetEmail(
    email: string,
    rawToken: string,
  ): Promise<void> {
    const apiKey = this.config.get<string>('RESEND_API_KEY');
    const from = this.config.get<string>('EMAIL_FROM');
    const resetUrl = this.config.get<string>('PASSWORD_RESET_URL');

    if (!apiKey || !from || !resetUrl) {
      this.logger.error(
        'Password reset email is not configured; message was not sent.',
      );
      return;
    }

    const separator = resetUrl.includes('?') ? '&' : '?';
    const url = `${resetUrl}${separator}token=${encodeURIComponent(rawToken)}`;

    try {
      const response = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${apiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          from,
          to: [email],
          subject: 'Redefinição de palavra-passe — NhaCarro',
          html: this.buildHtml(url),
        }),
      });

      if (!response.ok) {
        this.logger.error(
          `Password reset email delivery failed with status ${response.status}.`,
        );
      }
    } catch (error) {
      this.logger.error(
        'Password reset email delivery failed due to a network/provider error.',
        error instanceof Error ? error.stack : undefined,
      );
    }
  }

  private buildHtml(resetUrl: string): string {
    return `<!doctype html>
<html lang="pt">
<head>
  <meta charset="utf-8">
  <meta name="referrer" content="no-referrer">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Redefinição de palavra-passe</title>
</head>
<body style="font-family:Arial,sans-serif;line-height:1.5;color:#1f2937">
  <h2>Redefinição de palavra-passe</h2>
  <p>Recebemos um pedido para redefinir a palavra-passe da sua conta NhaCarro.</p>
  <p>Este link é válido durante 30 minutos e só pode ser utilizado uma vez.</p>
  <p><a href="${resetUrl}">Redefinir palavra-passe</a></p>
  <p>Se não fez este pedido, pode ignorar este e-mail.</p>
</body>
</html>`;
  }
}
