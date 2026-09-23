import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { MtnMomoProvider } from './mtn-momo.provider';
import { OrangeMoneyProvider } from './orange-money.provider';
import { PaymentMethod, PaymentProvider } from './payment-provider';

@Injectable()
export class PaymentProviderFactory {
  constructor(
    private readonly orangeMoney: OrangeMoneyProvider,
    private readonly mtnMomo: MtnMomoProvider,
  ) {}

  get(method: PaymentMethod): PaymentProvider {
    const provider = method === 'ORANGE_MONEY' ? this.orangeMoney : this.mtnMomo;

    if (!provider.isEnabled()) {
      throw new ServiceUnavailableException(
        `O provedor ${method} ainda não está configurado para pagamentos reais.`,
      );
    }

    return provider;
  }
}
