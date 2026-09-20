import { Controller, Get, UseGuards } from '@nestjs/common';
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
}
