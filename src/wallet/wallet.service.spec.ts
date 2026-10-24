import { BadRequestException, ServiceUnavailableException, UnauthorizedException } from '@nestjs/common';
import { WalletService } from './wallet.service';

function queryChain(result: unknown) {
  const c: any = {};
  c.select = jest.fn(() => c);
  c.eq = jest.fn(() => c);
  c.order = jest.fn(() => Promise.resolve(result));
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

  const envKeys = [
    'NODE_ENV',
    'WALLET_TEST_MODE',
    'WALLET_WEBHOOK_URL',
    'WALLET_WEBHOOK_SECRET',
  ] as const;
  let originalEnv: Partial<Record<(typeof envKeys)[number], string | undefined>>;

  beforeEach(() => {
    originalEnv = Object.fromEntries(envKeys.map((key) => [key, process.env[key]]));
    jest.clearAllMocks();
    supabase = { getUserClient: jest.fn(), getClient: jest.fn() };
    service = new WalletService(supabase as never, paymentProviders as never);
  });

  afterEach(() => {
    for (const key of envKeys) {
      const value = originalEnv[key];
      if (value === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = value;
      }
    }
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
    expect(result.transactions).toEqual([
      expect.objectContaining({ id: 'tx-1', valor: -2500, tipo: 'PAGAMENTO_VIAGEM' }),
    ]);
    expect(result.balance).toBe(10000);
  });

  it('rejects commission debt queries from non-drivers', async () => {
    await expect(service.getCommissionDebts(passenger)).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
    expect(supabase.getClient).not.toHaveBeenCalled();
  });

  it('lists only the authenticated driver commission debts and totals pending amounts', async () => {
    const debts = queryChain({
      data: [
        { id: 'debt-1', motorista_id: 'driver-1', valor: '500.00', status: 'PENDENTE' },
        { id: 'debt-2', motorista_id: 'driver-1', valor: '200.00', status: 'PAGA' },
      ],
      error: null,
    });
    supabase.getClient.mockReturnValue({ from: jest.fn().mockReturnValue(debts) });

    const result = await service.getCommissionDebts(driver);

    expect(debts.eq).toHaveBeenCalledWith('motorista_id', 'driver-1');
    expect(debts.order).toHaveBeenCalledWith('criado_em', { ascending: false });
    expect(result.pendingTotal).toBe(500);
    expect(result.debts).toHaveLength(2);
  });

  it('does not return fabricated commission debt totals when the database query fails', async () => {
    const debts = queryChain({ data: null, error: { message: 'database unavailable' } });
    supabase.getClient.mockReturnValue({ from: jest.fn().mockReturnValue(debts) });

    await expect(service.getCommissionDebts(driver)).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
  });

  it('rejects admin commission debt list access from non-admin users', async () => {
    await expect(service.getCommissionDebtsForAdmin(driver)).rejects.toMatchObject({
      status: 403,
    });
    expect(supabase.getClient).not.toHaveBeenCalled();
  });

  it('returns pending commission debts and totals for an admin', async () => {
    const debts = queryChain({
      data: [
        { id: 'debt-1', valor: '500.00', status: 'PENDENTE', motorista: { nome: 'Motorista A' } },
        { id: 'debt-2', valor: '200.00', status: 'PAGA', motorista: { nome: 'Motorista B' } },
      ],
      error: null,
    });
    supabase.getClient.mockReturnValue({ from: jest.fn().mockReturnValue(debts) });

    const result = await service.getCommissionDebtsForAdmin({
      sub: 'admin-1',
      email: 'admin@example.com',
      role: 'admin',
    });

    expect(debts.order).toHaveBeenCalledWith('criado_em', { ascending: false });
    expect(result.pendingTotal).toBe(500);
    expect(result.pendingCount).toBe(1);
    expect(result.debts).toHaveLength(2);
  });

  it('rejects commission debt settlement from non-admin users', async () => {
    await expect(
      service.settleCommissionDebt(
        { debtId: 'debt-1', paymentMethod: 'DINHEIRO' },
        driver,
      ),
    ).rejects.toMatchObject({ status: 403 });
    expect(supabase.getClient).not.toHaveBeenCalled();
  });

  it('records an admin-confirmed commission payment through the idempotent RPC', async () => {
    const rpc = jest.fn().mockResolvedValue({
      data: [{
        debt_id: 'debt-1',
        status: 'PAGA',
        amount: '500.00',
        paid_at: '2026-10-21T20:00:00Z',
        payment_method: 'DINHEIRO',
        payment_reference: null,
        paid_by: 'admin-1',
        already_paid: false,
      }],
      error: null,
    });
    supabase.getClient.mockReturnValue({ rpc });

    const result = await service.settleCommissionDebt(
      { debtId: 'debt-1', paymentMethod: 'DINHEIRO' },
      { sub: 'admin-1', email: 'admin@example.com', role: 'admin' },
    );

    expect(rpc).toHaveBeenCalledWith('settle_driver_commission_debt', {
      p_debt_id: 'debt-1',
      p_admin_id: 'admin-1',
      p_payment_method: 'DINHEIRO',
      p_payment_reference: null,
    });
    expect(result).toMatchObject({
      debtId: 'debt-1',
      status: 'PAGA',
      amount: '500.00',
      paymentMethod: 'DINHEIRO',
      alreadyPaid: false,
    });
  });

  it('requires a transfer reference before recording a commission payment', async () => {
    await expect(
      service.settleCommissionDebt(
        { debtId: 'debt-1', paymentMethod: 'TRANSFERENCIA' },
        { sub: 'admin-1', email: 'admin@example.com', role: 'admin' },
      ),
    ).rejects.toMatchObject({ status: 400 });
    expect(supabase.getClient).not.toHaveBeenCalled();
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

  it('blocks test top-ups in production before calling the database even when test mode is enabled', async () => {
    process.env.NODE_ENV = 'production';
    process.env.WALLET_TEST_MODE = 'true';

    await expect(
      service.testTopUp({ amount: 1000, method: 'orangeMoney' }, passenger),
    ).rejects.toMatchObject({
      status: 503,
      message: 'Recarga de teste indisponível em produção.',
    });

    expect(supabase.getClient).not.toHaveBeenCalled();
  });

  it('blocks test top-ups when test mode is disabled before calling the database', async () => {
    process.env.NODE_ENV = 'test';
    delete process.env.WALLET_TEST_MODE;

    await expect(
      service.testTopUp({ amount: 1000, method: 'orangeMoney' }, passenger),
    ).rejects.toBeInstanceOf(ServiceUnavailableException);

    expect(supabase.getClient).not.toHaveBeenCalled();
  });

  it('allows a mocked test top-up only outside production when test mode is enabled', async () => {
    process.env.NODE_ENV = 'test';
    process.env.WALLET_TEST_MODE = 'true';
    const rpc = jest.fn().mockResolvedValue({
      data: [{
        balance: 1000,
        amount: 1000,
        type: 'RECARGA_ORANGE',
        transaction_id: 'test-tx-1',
        reference: 'test-ref-1',
      }],
      error: null,
    });
    supabase.getClient.mockReturnValue({ rpc });

    await expect(
      service.testTopUp({ amount: 1000, method: 'orangeMoney' }, passenger),
    ).resolves.toEqual({
      balance: 1000,
      amount: 1000,
      type: 'RECARGA_ORANGE',
      transactionId: 'test-tx-1',
      reference: 'test-ref-1',
      testMode: true,
    });

    expect(rpc).toHaveBeenCalledWith('test_top_up_wallet', {
      p_user_id: 'passenger-1',
      p_amount: 1000,
      p_type: 'RECARGA_ORANGE',
    });
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
        commission_debt_id: null,
        commission_debt_status: null,
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
      commissionDebtId: null,
      commissionDebtStatus: null,
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
  it('returns the same pending commission debt details from the settlement RPC', async () => {
    const rpc = jest.fn()
      .mockResolvedValueOnce({
        data: [{
          ride_id: 'ride-cash-1',
          status: 'CONCLUIDA',
          settled: false,
          amount: 2500,
          balance: 1000,
          transaction_id: null,
          reason: 'PAGAMENTO_EM_DINHEIRO_DIVIDA_COMISSAO_PENDENTE',
          commission: 500,
          driver_credit: 0,
          driver_balance: 1000,
          driver_transaction_id: null,
          commission_debt_id: 'debt-1',
          commission_debt_status: 'PENDENTE',
        }],
        error: null,
      })
      .mockResolvedValueOnce({
        data: [{
          ride_id: 'ride-cash-1',
          status: 'CONCLUIDA',
          settled: false,
          amount: 2500,
          balance: 1000,
          transaction_id: null,
          reason: 'PAGAMENTO_EM_DINHEIRO_DIVIDA_COMISSAO_JA_REGISTADA',
          commission: 500,
          driver_credit: 0,
          driver_balance: 1000,
          driver_transaction_id: null,
          commission_debt_id: 'debt-1',
          commission_debt_status: 'PENDENTE',
        }],
        error: null,
      });
    supabase.getClient.mockReturnValue({ rpc });

    const first = await service.completeRideSettlement('ride-cash-1', driver);
    const second = await service.completeRideSettlement('ride-cash-1', driver);

    expect(rpc).toHaveBeenCalledTimes(2);
    expect(rpc).toHaveBeenNthCalledWith(1, 'complete_ride_and_settle_wallet', {
      p_ride_id: 'ride-cash-1',
      p_actor_id: 'driver-1',
    });
    expect(first).toMatchObject({
      settled: false,
      commission: 500,
      driverBalance: 1000,
      commissionDebtId: 'debt-1',
      commissionDebtStatus: 'PENDENTE',
    });
    expect(second.commissionDebtId).toBe(first.commissionDebtId);
    expect(second.commissionDebtStatus).toBe('PENDENTE');
  });

});
