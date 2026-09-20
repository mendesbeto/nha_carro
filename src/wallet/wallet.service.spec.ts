import { BadRequestException } from '@nestjs/common';
import { WalletService } from './wallet.service';

function queryChain(result: unknown) {
  const c: any = {};
  c.select = jest.fn(() => c);
  c.eq = jest.fn(() => c);
  c.order = jest.fn().mockResolvedValue(result);
  c.single = jest.fn().mockResolvedValue(result);
  return c;
}

const passenger = { sub: 'passenger-1', email: 'p@example.com', role: 'passenger' as const };
const driver = { sub: 'driver-1', email: 'd@example.com', role: 'driver' as const };

describe('WalletService', () => {
  let supabase: { getUserClient: jest.Mock; getClient: jest.Mock };
  let service: WalletService;

  beforeEach(() => {
    jest.clearAllMocks();
    supabase = { getUserClient: jest.fn(), getClient: jest.fn() };
    service = new WalletService(supabase as never);
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
