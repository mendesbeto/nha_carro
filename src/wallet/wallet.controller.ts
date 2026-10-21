import { Controller, Get, Post, Body, Headers, Param, Query, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import {
  CurrentAccessToken,
  CurrentUser,
  CurrentUserPayload,
} from '../auth/current-user.decorator';
import { WalletService } from './wallet.service';

@Controller('api/wallet')
export class WalletController {
  constructor(private readonly walletService: WalletService) {}

  @Get()
  @UseGuards(JwtAuthGuard)
  getWallet(
    @CurrentUser() user: CurrentUserPayload,
    @CurrentAccessToken() accessToken: string,
  ) {
    return this.walletService.getWallet(user, accessToken);
  }

  @Get('commission-debts')
  @UseGuards(JwtAuthGuard)
  getCommissionDebts(@CurrentUser() user: CurrentUserPayload) {
    return this.walletService.getCommissionDebts(user);
  }

  @Get('admin/users')
  @UseGuards(JwtAuthGuard)
  getAdminUsers(
    @CurrentUser() user: CurrentUserPayload,
    @Query('profile') profile: string,
  ) {
    return this.walletService.getAdminUsers(user, profile);
  }

  @Get('admin/commission-debts')
  @UseGuards(JwtAuthGuard)
  getCommissionDebtsForAdmin(@CurrentUser() user: CurrentUserPayload) {
    return this.walletService.getCommissionDebtsForAdmin(user);
  }

  @Post('commission-debts/settle')
  @UseGuards(JwtAuthGuard)
  settleCommissionDebt(
    @Body() body: {
      debtId?: string;
      paymentMethod?: 'DINHEIRO' | 'TRANSFERENCIA' | 'OUTRO';
      paymentReference?: string;
    },
    @CurrentUser() user: CurrentUserPayload,
  ) {
    return this.walletService.settleCommissionDebt(body, user);
  }

  @Post('topup')
  @UseGuards(JwtAuthGuard)
  createTopUp(
    @Body() body: { amount?: number; method?: 'orangeMoney' | 'mtnMoney'; idempotencyKey?: string },
    @CurrentUser() user: CurrentUserPayload,
    @CurrentAccessToken() accessToken: string,
  ) {
    return this.walletService.createTopUp(body, user, accessToken);
  }

  @Post('webhooks/:provider')
  handleWebhook(
    @Param('provider') provider: string,
    @Headers('x-wallet-webhook-secret') secret: string | undefined,
    @Body() body: {
      eventId?: string;
      topupId?: string;
      providerReference?: string;
      status?: 'CONFIRMED' | 'FAILED' | 'PENDING';
      amount?: number | string;
      payload?: unknown;
    },
  ) {
    return this.walletService.handleWebhook(provider, secret, body);
  }

  @Post('test-topup')
  @UseGuards(JwtAuthGuard)
  testTopUp(
    @Body() body: { amount?: number; method?: 'orangeMoney' | 'mtnMoney' },
    @CurrentUser() user: CurrentUserPayload,
  ) {
    return this.walletService.testTopUp(body, user);
  }
}
