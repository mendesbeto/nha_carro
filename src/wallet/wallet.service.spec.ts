import { BadRequestException, ServiceUnavailableException } from '@nestjs/common';
import { WalletService } from './wallet.service';

function queryChain(result: unknown) {
  const c: any = {};
  c.select = jest.fn(() => c);
  c.eq = jest.fn(() => c);
  c.order = jest.fn(() => c);
  c.in = jest.fn(() => c);
  c.limit = jest.fn(() => c);
  c.single = jest.fn().mockResolvedValue(result);
  c.maybeSingle = jest.fn().mockResolvedValue(result);
  c.insert = jest.fn(() => c);
  c.update = jest.fn(() => c);
  return c;
}

const passenger = { sub: 'passenger-1', email: 'p@example.com', role: 'passenger' as const };
const driver = { sub: 'driver-1', email: 'd@example.com', role: 'driver' as const };

describe('WalletService', () => {
  let supabase: { getUserClient: jest.Mock; getClient: jest.Mock };
  let service: WalletService;
  const paymentProviders = { get: jest.fn() };

  beforeEach(() => {
    jest.clearAllMocks();
    supabase = { getUserClient: jest.fn(), getClient: jest.fn() };
    service = new WalletService(supabase as never, paymentProviders as never);
  });

  it('loads wallet balance and transaction history for the authenticated user', async () => {
    const profile = queryChain({ data: { saldo_carteira: 10000 }, error: null });
    const transactions = queryChain({
      data: [{ id: 'tx-1', valor: -2500, tipo: 'PAGAMENTO_VIAGEM', referencia_provedor: 'RIDE:ride-1', criado_em: '2026-09-20T10:00:00Z' }],
      error: null,
    });
    supabase.getUserClient.mockReturnValue({
      from: jest.fn().mockReturnValueOnce(profile).mockReturnValueOnce(transactions),
    });

    const result = await service.getWallet(passenger, 'access-token');

    expect(profile.eq).toHaveBeenCalledWith('id', 'passenger-1');
    expect(transactions.eq).toHaveBeenCalledWith('usuario_id', 'passenger-1');
    expect(transactions.order).toHaveBeenCalledWith('criado_em', { ascending: false });
    expect(result.transactions).toHaveLength(1);
    expect(result.balance).toBe(10000);
  });

  it('rejects wallet access when the profile cannot be loaded', async () => {
    supabase.getUserClient.mockReturnValue({
      from: jest.fn().mockReturnValue(queryChain({ data: null, error: { message: 'not found' } })),
    });
    await expect(service.getWallet(passenger, 'access-token')).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects top-up before database creation when the provider is unavailable', async () => {
    paymentProviders.get.mockImplementation(() => {
      throw new ServiceUnavailableException('Provedor não configurado.');
    });

    await expect(
      service.createTopUp(
        { amount: 2500, method: 'orangeMoney', idempotencyKey: 'idem-1' },
        passenger,
        'access-token',
      ),
    ).rejects.toBeInstanceOf(ServiceUnavailableException);

    expect(supabase.getClient).not.toHaveBeenCalled();
  });

  it('reuses an existing top-up for the same user and idempotency key', async () => {
    const existing = queryChain({
      data: {
        id: 'topup-1',
        valor: '2500.00',
        metodo: 'ORANGE_MONEY',
        status: 'PENDENTE',
        referencia_provedor: null,
        checkout_url: null,
        criado_em: '2026-09-23T00:00:00Z',
      },
      error: null,
    });
    supabase.getClient.mockReturnValue({
      from: jest.fn().mockReturnValue(existing),
    });
    paymentProviders.get.mockReturnValue({ createPayment: jest.fn() });

    const result = await service.createTopUp(
      { amount: 2500, method: 'orangeMoney', idempotencyKey: 'idem-1' },
      passenger,
      'access-token',
    );

    expect(result).toEqual({
      id: 'topup-1',
      valor: '2500.00',
      metodo: 'ORANGE_MONEY',
      status: 'PENDENTE',
      referencia_provedor: null,
      checkout_url: null,
      criado_em: '2026-09-23T00:00:00Z',
      reused: true,
    });
    expect(supabase.getClient).toHaveBeenCalledTimes(1);
  });

  it('starts a provider payment and persists its reference', async () => {
    process.env.WALLET_WEBHOOK_URL = 'https://nha-carro.onrender.com/api/wallet/webhooks/';
    const provider = {
      createPayment: jest.fn().mockResolvedValue({
        providerReference: 'orange-ref-1',
        status: 'PROCESSING',
        checkoutUrl: 'https://checkout.example.test/1',
        raw: { accepted: true },
      }),
    };
    paymentProviders.get.mockReturnValue(provider);

    const existing = queryChain({ data: null, error: null });
    const profile = queryChain({ data: { telefone: '+245900000000' }, error: null });
    const created = queryChain({
      data: {
        id: 'topup-1',
        valor: '2500.00',
        metodo: 'ORANGE_MONEY',
        status: 'PENDENTE',
        referencia_provedor: null,
        checkout_url: null,
        criado_em: '2026-09-23T00:00:00Z',
      },
      error: null,
    });
    const updated = queryChain({
      data: {
        id: 'topup-1',
        valor: '2500.00',
        metodo: 'ORANGE_MONEY',
        status: 'PROCESSANDO',
        referencia_provedor: 'orange-ref-1',
        checkout_url: 'https://checkout.example.test/1',
        criado_em: '2026-09-23T00:00:00Z',
      },
      error: null,
    });

    const from = jest.fn()
      .mockReturnValueOnce(existing)
      .mockReturnValueOnce(profile)
      .mockReturnValueOnce(created)
      .mockReturnValueOnce(updated);
    supabase.getClient.mockReturnValue({ from });

    const result = await service.createTopUp(
      { amount: 2500, method: 'orangeMoney', idempotencyKey: 'idem-2' },
      passenger,
      'access-token',
    );

    expect(provider.createPayment).toHaveBeenCalledWith(expect.objectContaining({
      amount: 2500,
      currency: 'XOF',
      customerPhone: '+245900000000',
      callbackUrl: 'https://nha-carro.onrender.com/api/wallet/webhooks/ORANGE_MONEY',
    }));
    expect(result.status).toBe('PROCESSANDO');
    expect(result.referencia_provedor).toBe('orange-ref-1');
  });

  it('marks a provider failure without crediting the wallet', async () => {
    process.env.WALLET_WEBHOOK_URL = 'https://nha-carro.onrender.com/api/wallet/webhooks';
    paymentProviders.get.mockReturnValue({
      createPayment: jest.fn().mockRejectedValue(new Error('provider timeout')),
    });

    const existing = queryChain({ data: null, error: null });
    const profile = queryChain({ data: { telefone: '+245900000000' }, error: null });
    const created = queryChain({
      data: {
        id: 'topup-2',
        valor: '3000.00',
        metodo: 'ORANGE_MONEY',
        status: 'PENDENTE',
        referencia_provedor: null,
        checkout_url: null,
        criado_em: '2026-09-23T00:00:00Z',
      },
      error: null,
    });
    const failed = queryChain({ data: [], error: null });

    supabase.getClient.mockReturnValue({
      from: jest.fn()
        .mockReturnValueOnce(existing)
        .mockReturnValueOnce(profile)
        .mockReturnValueOnce(created)
        .mockReturnValueOnce(failed),
    });

    await expect(
      service.createTopUp(
        { amount: 3000, method: 'orangeMoney', idempotencyKey: 'idem-3' },
        passenger,
        'access-token',
      ),
    ).rejects.toBeInstanceOf(ServiceUnavailableException);

    expect(failed.update).toHaveBeenCalledWith(expect.objectContaining({
      status: 'FALHOU',
    }));
  });

  it('confirms a webhook through the idempotent database RPC', async () => {
    process.env.WALLET_WEBHOOK_SECRET = 'test-secret';
    const lookup = queryChain({
      data: {
        id: 'topup-3',
        usuario_id: 'passenger-1',
        valor: '2500.00',
        metodo: 'ORANGE_MONEY',
        status: 'PROCESSANDO',
        referencia_provedor: null,
      },
      error: null,
    });
    const rpc = jest.fn().mockResolvedValue({
      data: [{
        topup_id: 'topup-3',
        status: 'CONFIRMADA',
        balance: '5000.00',
        transaction_id: 'tx-topup-3',
        already_confirmed: false,
      }],
      error: null,
    });
    supabase.getClient.mockReturnValue({ from: jest.fn().mockReturnValue(lookup), rpc });

    const result = await service.handleWebhook('orange-money', 'test-secret', {
      topupId: 'topup-3',
      providerReference: 'orange-ref-3',
      status: 'CONFIRMED',
      amount: 2500,
      eventId: 'evt-3',
    });

    expect(rpc).toHaveBeenCalledWith('confirm_wallet_top_up', {
      p_topup_id: 'topup-3',
      p_provider_reference: 'orange-ref-3',
      p_amount: 2500,
      p_provider_response: expect.objectContaining({
        topupId: 'topup-3',
        providerReference: 'orange-ref-3',
        status: 'CONFIRMED',
        amount: 2500,
        eventId: 'evt-3',
      }),
    });
    expect(result).toEqual(expect.objectContaining({
      accepted: true,
      status: 'CONFIRMADA',
      balance: '5000.00',
      transactionId: 'tx-topup-3',
      alreadyConfirmed: false,
      eventId: 'evt-3',
    }));
  });

  it('rejects an unauthorized webhook before touching the database', async () => {
    process.env.WALLET_WEBHOOK_SECRET = 'test-secret';

    await expect(
      service.handleWebhook('orange-money', 'wrong-secret', {
        topupId: 'topup-4',
        status: 'CONFIRMED',
        providerReference: 'ref-4',
        amount: 1000,
      }),
    ).rejects.toMatchObject({ status: 401 });

    expect(supabase.getClient).not.toHaveBeenCalled();
  });

  it('rejects settlement for non-drivers before calling the database RPC', async () => {
    await expect(service.completeRideSettlement('ride-1', passenger)).rejects.toBeInstanceOf(BadRequestException);
    expect(supabase.getClient).not.toHaveBeenCalled();
  });

  it('calls settlement RPC with the authenticated driver and maps commission details', async () => {
    const rpc = jest.fn().mockResolvedValue({
      data: [{
        ride_id: 'ride-1',
        status: 'CONCLUIDA',
        settled: true,
        amount: 2800,
        balance: 7200,
        transaction_id: 'tx-passenger',
        reason: 'LIQUIDADA',
        commission: 700,
        driver_credit: 2800,
        driver_balance: 7800,
        driver_transaction_id: 'tx-driver',
      }],
      error: null,
    });
    supabase.getClient.mockReturnValue({ rpc });

    await expect(service.completeRideSettlement('ride-1', driver)).resolves.toEqual({
      rideId: 'ride-1',
      status: 'CONCLUIDA',
      settled: true,
      amount: 2800,
      balance: 7200,
      transactionId: 'tx-passenger',
      reason: 'LIQUIDADA',
      commission: 700,
      driverCredit: 2800,
      driverBalance: 7800,
      driverTransactionId: 'tx-driver',
    });

    expect(rpc).toHaveBeenCalledWith('complete_ride_and_settle_wallet', {
      p_ride_id: 'ride-1',
      p_actor_id: 'driver-1',
    });
  });

  it('converts database settlement errors into BadRequestException', async () => {
    const rpc = jest.fn().mockResolvedValue({ data: null, error: { message: 'Saldo insuficiente.' } });
    supabase.getClient.mockReturnValue({ rpc });
    await expect(service.completeRideSettlement('ride-1', driver)).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects an empty settlement response', async () => {
    const rpc = jest.fn().mockResolvedValue({ data: [], error: null });
    supabase.getClient.mockReturnValue({ rpc });
    await expect(service.completeRideSettlement('ride-1', driver)).rejects.toBeInstanceOf(BadRequestException);
  });
});
