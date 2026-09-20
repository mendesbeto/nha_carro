import { BadRequestException, ForbiddenException } from '@nestjs/common';
import { RidesService } from './rides.service';

function queryChain(result: unknown) {
  const c: any = {};
  c.select = jest.fn(() => c);
  c.eq = jest.fn(() => c);
  c.is = jest.fn(() => c);
  c.in = jest.fn(() => c);
  c.order = jest.fn().mockResolvedValue(result);
  c.maybeSingle = jest.fn().mockResolvedValue(result);
  c.single = jest.fn().mockResolvedValue(result);
  c.insert = jest.fn(() => c);
  c.update = jest.fn(() => c);
  return c;
}

const passenger = { sub: 'passenger-1', email: 'p@example.com', role: 'passenger' as const };
const driver = { sub: 'driver-1', email: 'd@example.com', role: 'driver' as const };
const token = 'access-token';

describe('RidesService', () => {
  let supabase: { getUserClient: jest.Mock };
  let wallet: { completeRideSettlement: jest.Mock };
  let service: RidesService;

  beforeEach(() => {
    jest.clearAllMocks();
    supabase = { getUserClient: jest.fn() };
    wallet = { completeRideSettlement: jest.fn() };
    service = new RidesService(supabase as never, wallet as never);
  });

  it('rejects available rides for passengers', async () => {
    await expect(service.available(passenger, token)).rejects.toBeInstanceOf(ForbiddenException);
    expect(supabase.getUserClient).not.toHaveBeenCalled();
  });

  it('loads only unassigned requested rides for drivers', async () => {
    const query = queryChain({
      data: [{ id: 'ride-1', passageiro_id: 'passenger-1', origem_coords: { type: 'Point' }, destino_coords: null, valor_total: 2500, forma_pagamento: 'DINHEIRO', status: 'SOLICITADA', criado_em: '2026-09-20T10:00:00Z' }],
      error: null,
    });
    supabase.getUserClient.mockReturnValue({ from: jest.fn().mockReturnValue(query) });

    const result = await service.available(driver, token);

    expect(query.eq).toHaveBeenCalledWith('status', 'SOLICITADA');
    expect(query.is).toHaveBeenCalledWith('motorista_id', null);
    expect(query.order).toHaveBeenCalledWith('criado_em', { ascending: true });
    expect(result.rides[0]).toMatchObject({ rideId: 'ride-1', valor: 2500, status: 'SOLICITADA' });
  });

  it('accepts a requested ride and applies the race-safe predicates', async () => {
    const current = queryChain({
      data: { id: 'ride-1', passageiro_id: 'passenger-1', motorista_id: null, status: 'SOLICITADA' },
      error: null,
    });
    const update = queryChain({
      data: { id: 'ride-1', passageiro_id: 'passenger-1', motorista_id: 'driver-1', status: 'ACEITA' },
      error: null,
    });
    const client = { from: jest.fn().mockReturnValueOnce(current).mockReturnValueOnce(update) };
    supabase.getUserClient.mockReturnValue(client);

    const result = await service.accept('ride-1', driver, token);

    expect(update.update).toHaveBeenCalledWith({ status: 'ACEITA', motorista_id: 'driver-1' });
    expect(update.eq).toHaveBeenCalledWith('status', 'SOLICITADA');
    expect(update.is).toHaveBeenCalledWith('motorista_id', null);
    expect(result).toEqual({ rideId: 'ride-1', status: 'ACEITA', passageiroId: 'passenger-1', motoristaId: 'driver-1' });
  });

  it('rejects an accept when the current ride was already taken', async () => {
    const current = queryChain({
      data: { id: 'ride-1', passageiro_id: 'passenger-1', motorista_id: 'driver-2', status: 'ACEITA' },
      error: null,
    });
    supabase.getUserClient.mockReturnValue({ from: jest.fn().mockReturnValue(current) });

    await expect(service.accept('ride-1', driver, token)).rejects.toBeInstanceOf(BadRequestException);
    expect(current.update).not.toHaveBeenCalled();
  });

  it('rejects a race where start no longer matches ACEITA + current driver', async () => {
    const current = queryChain({
      data: { id: 'ride-1', passageiro_id: 'passenger-1', motorista_id: 'driver-1', status: 'ACEITA' },
      error: null,
    });
    const update = queryChain({ data: null, error: { message: '0 rows returned' } });
    supabase.getUserClient.mockReturnValue({ from: jest.fn().mockReturnValueOnce(current).mockReturnValueOnce(update) });

    await expect(service.start('ride-1', driver, token)).rejects.toBeInstanceOf(BadRequestException);
    expect(update.update).toHaveBeenCalledWith({ status: 'EM_ANDAMENTO' });
    expect(update.eq).toHaveBeenCalledWith('status', 'ACEITA');
    expect(update.eq).toHaveBeenCalledWith('motorista_id', 'driver-1');
  });

  it('cancels only when passenger and state predicates still match', async () => {
    const current = queryChain({
      data: { id: 'ride-1', passageiro_id: 'passenger-1', motorista_id: null, status: 'SOLICITADA' },
      error: null,
    });
    const update = queryChain({
      data: { id: 'ride-1', passageiro_id: 'passenger-1', motorista_id: null, status: 'CANCELADA' },
      error: null,
    });
    supabase.getUserClient.mockReturnValue({ from: jest.fn().mockReturnValueOnce(current).mockReturnValueOnce(update) });

    await service.cancel('ride-1', passenger, token);

    expect(update.update).toHaveBeenCalledWith({ status: 'CANCELADA' });
    expect(update.eq).toHaveBeenCalledWith('passageiro_id', 'passenger-1');
    expect(update.in).toHaveBeenCalledWith('status', ['SOLICITADA', 'ACEITA']);
  });

  it('rejects cancellation by a driver', async () => {
    await expect(service.cancel('ride-1', driver, token)).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('persists a ride with server-side fare, commission and payment mapping', async () => {
    const profile = queryChain({ data: { id: 'passenger-1' }, error: null });
    const insert = queryChain({ data: { id: 'ride-1' }, error: null });
    supabase.getUserClient.mockReturnValue({ from: jest.fn().mockReturnValueOnce(profile).mockReturnValueOnce(insert) });

    const result = await service.request({
      destination: 'Centro',
      category: 'confort',
      paymentMethod: 'orangeMoney',
      originLat: 12.3,
      originLng: -15.4,
      destinationLat: 12.4,
      destinationLng: -15.5,
    }, passenger, token);

    expect(insert.insert).toHaveBeenCalledWith(expect.objectContaining({
      passageiro_id: 'passenger-1',
      valor_total: 3500,
      valor_comissao: 700,
      forma_pagamento: 'ORANGE_MONEY',
      status: 'SOLICITADA',
    }));
    expect(result).toMatchObject({ rideId: 'ride-1', persisted: true, estimatedFare: 3500 });
  });

  it('requires both destination coordinates together', async () => {
    await expect(service.request({
      destination: 'Centro',
      originLat: 12,
      originLng: -15,
      destinationLat: 12.4,
    }, passenger, token)).rejects.toBeInstanceOf(BadRequestException);
  });

  it('delegates completion and settlement to WalletService', async () => {
    wallet.completeRideSettlement.mockResolvedValue({ rideId: 'ride-1', settled: true, driverCredit: 2000 });
    await expect(service.complete('ride-1', driver)).resolves.toEqual({
      rideId: 'ride-1',
      settled: true,
      driverCredit: 2000,
    });
  });
});
