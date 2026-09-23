import { Controller, Get, Post, Body, Headers, Param, UseGuards } from '@nestjs/common';
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
