export type PaymentMethod = 'ORANGE_MONEY' | 'MTN_MONEY';

export type PaymentInitRequest = {
  amount: number;
  currency: string;
  reference: string;
  customerPhone?: string;
  callbackUrl: string;
};

export type PaymentInitResult = {
  providerReference: string;
  status: 'PENDING' | 'PROCESSING';
  checkoutUrl?: string;
  raw?: unknown;
};

export interface PaymentProvider {
  readonly method: PaymentMethod;
  createPayment(input: PaymentInitRequest): Promise<PaymentInitResult>;
}
