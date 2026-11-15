import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { JwtAuthGuard } from './jwt-auth.guard';
import { PasswordResetService } from './password-reset.service';
import { EmailService } from './email.service';
import { PasswordResetPageController } from './password-reset-page.controller';
import { EmailConfirmationPageController } from './email-confirmation-page.controller';

@Module({
  imports: [ConfigModule],
  controllers: [AuthController, PasswordResetPageController, EmailConfirmationPageController],
  providers: [AuthService, JwtAuthGuard, PasswordResetService, EmailService],
  exports: [AuthService, JwtAuthGuard],
})
export class AuthModule {}