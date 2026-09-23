import { Injectable } from '@nestjs/common';
import {
  PaymentInitRequest,
  PaymentInitResult,
  PaymentMethod,
  PaymentProvider,
} from './payment-provider';

@Injectable()
export class MtnMomoProvider implements PaymentProvider {
  readonly method: PaymentMethod = 'MTN_MONEY';

  isEnabled(): boolean {
    return process.env.MTN_MOMO_ENABLED === 'true' &&
      Boolean(process.env.MTN_MOMO_API_BASE_URL) &&
      Boolean(process.env.MTN_MOMO_SUBSCRIPTION_KEY) &&
      Boolean(process.env.MTN_MOMO_API_USER) &&
      Boolean(process.env.MTN_MOMO_API_KEY);
  }

  async createPayment(_input: PaymentInitRequest): Promise<PaymentInitResult> {
    throw new Error(
      'MTN MoMo ainda não foi conectado ao endpoint oficial de pagamento. Configure o adapter após validar o contrato da API.',
    );
  }
}
