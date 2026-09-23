import { Module } from '@nestjs/common';
import { SupabaseModule } from '../supabase/supabase.module';
import { WalletController } from './wallet.controller';
import { WalletService } from './wallet.service';
import { MtnMomoProvider } from './mtn-momo.provider';
import { OrangeMoneyProvider } from './orange-money.provider';
import { PaymentProviderFactory } from './payment-provider.factory';

@Module({
  imports: [SupabaseModule],
  controllers: [WalletController],
  providers: [
    WalletService,
    OrangeMoneyProvider,
    MtnMomoProvider,
    PaymentProviderFactory,
  ],
  exports: [WalletService],
})
export class WalletModule {}
