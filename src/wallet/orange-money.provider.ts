import { Injectable } from '@nestjs/common';
import {
  PaymentInitRequest,
  PaymentInitResult,
  PaymentMethod,
  PaymentProvider,
} from './payment-provider';

@Injectable()
export class OrangeMoneyProvider implements PaymentProvider {
  readonly method: PaymentMethod = 'ORANGE_MONEY';

  isEnabled(): boolean {
    return process.env.ORANGE_MONEY_ENABLED === 'true' &&
      Boolean(process.env.ORANGE_CLIENT_ID) &&
      Boolean(process.env.ORANGE_CLIENT_SECRET) &&
      Boolean(process.env.ORANGE_MERCHANT_ID) &&
      Boolean(process.env.ORANGE_API_BASE_URL);
  }

  async createPayment(_input: PaymentInitRequest): Promise<PaymentInitResult> {
    throw new Error(
      'Orange Money ainda não foi conectado ao endpoint oficial de pagamento. Configure o adapter após validar as credenciais e o contrato da API.',
    );
  }
}
