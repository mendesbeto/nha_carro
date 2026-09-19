import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { JwtAuthGuard } from './jwt-auth.guard';
import { RefreshTokenService } from './refresh-token.service';
import { PasswordResetService } from './password-reset.service';
import { EmailService } from './email.service';
import { PasswordResetPageController } from './password-reset-page.controller';

@Module({
  imports: [ConfigModule],
  controllers: [AuthController, PasswordResetPageController],
  providers: [
    AuthService,
    JwtAuthGuard,
    // Kept temporarily for the legacy password-reset flow. It will be removed
    // after the Supabase Auth recovery flow is migrated in the next step.
    RefreshTokenService,
    PasswordResetService,
    EmailService,
  ],
  exports: [AuthService, JwtAuthGuard],
})
export class AuthModule {}
