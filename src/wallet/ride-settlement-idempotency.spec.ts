import { WalletService } from './wallet.service';

const driver = {
  sub: 'driver-idempotency-test',
  email: 'driver@example.test',
  role: 'driver' as const,
};

describe('ride settlement idempotency contract', () => {
  it('sends repeated completion attempts for the same ride to the same atomic database RPC', async () => {
    const firstSettlement = {
      ride_id: 'ride-idempotency-test',
      status: 'CONCLUIDA',
      settled: true,
      amount: 2000,
      balance: 8000,
      transaction_id: 'tx-passenger-once',
      reason: 'LIQUIDADA',
      commission: 500,
      driver_credit: 2000,
      driver_balance: 9500,
      driver_transaction_id: 'tx-driver-once',
    };

    // Simulate the database returning the original ledger references when a
    // retry reaches an already-settled ride. The database RPC is responsible
    // for enforcing this behavior atomically; this test checks the API contract.
    const rpc = jest
      .fn()
      .mockResolvedValueOnce({ data: [firstSettlement], error: null })
      .mockResolvedValueOnce({ data: [firstSettlement], error: null });
    const supabase = {
      getClient: jest.fn().mockReturnValue({ rpc }),
    };
    const service = new WalletService(supabase as never, { get: jest.fn() } as never);

    const first = await service.completeRideSettlement('ride-idempotency-test', driver);
    const retry = await service.completeRideSettlement('ride-idempotency-test', driver);

    expect(rpc).toHaveBeenCalledTimes(2);
    expect(rpc).toHaveBeenNthCalledWith(1, 'complete_ride_and_settle_wallet', {
      p_ride_id: 'ride-idempotency-test',
      p_actor_id: driver.sub,
    });
    expect(rpc).toHaveBeenNthCalledWith(2, 'complete_ride_and_settle_wallet', {
      p_ride_id: 'ride-idempotency-test',
      p_actor_id: driver.sub,
    });
    expect(first.transactionId).toBe('tx-passenger-once');
    expect(retry.transactionId).toBe(first.transactionId);
    expect(retry.driverTransactionId).toBe(first.driverTransactionId);
    expect(retry.commission).toBe(first.commission);
    expect(retry.driverCredit).toBe(first.driverCredit);
  });
});
