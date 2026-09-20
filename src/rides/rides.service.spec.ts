import { BadRequestException, ForbiddenException } from '@nestjs/common';
import { RidesService } from './rides.service';

function chain(result: unknown) {
  const c: any = {};
  c.select = jest.fn(() => c);
  c.eq = jest.fn(() => c);
  c.is = jest.fn(() => c);
  c.in = jest.fn(() => c);
  c.order = jest.fn(() => c);
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
    const rides = [{ id: 'ride-1', passageiro_id: 'passenger-1', origem_coords: { type: 'Point' }, destino_coords: null, valor_total: 2500, forma_pagamento: 'DINHEIRO', status: 'SOLICITADA', criado_em: '2026-09-20T10:00:00Z' }];
    const c = chain({ data: rides, error: null });
    supabase.getUserClient.mockReturnValue(c);

    const result = await service.available(driver, token);

    expect(c.select).toHaveBeenCalled();
    expect(c.eq).toHaveBeenCalledWith('status', 'SOLICITADA');
    expect(c.is).toHaveBeenCalledWith('motorista_id', null);
    expect(c.order).toHaveBeenCalledWith('criado_em', { ascending: true });
    expect(result.rides[0]).toMatchObject({ rideId: 'ride-1', valor: 2500, status: 'SOLICITADA' });
  });

  it('accepts a requested ride and applies the race-safe predicates', async () => {
    const c = chain({
      data: { id: 'ride-1', passageiro_id: 'passenger-1', motorista_id: 'driver-1', status: 'ACEITA' },
      error: null,
    });
    supabase.getUserClient.mockReturnValue(c);
    c.maybeSingle.mockResolvedValueOnce({
      data: { id: 'ride-1', passageiro_id: 'passenger-1', motorista_id: null, status: 'SOLICITADA' },
      error: null,
    });

    const result = await service.accept('ride-1', driver, token);

    expect(c.update).toHaveBeenCalledWith({ status: 'ACEITA', motorista_id: 'driver-1' });
    expect(c.eq).toHaveBeenCalledWith('status', 'SOLICITADA');
    expect(c.is).toHaveBeenCalledWith('motorista_id', null);
    expect(result).toEqual({ rideId: 'ride-1', status: 'ACEITA', passageiroId: 'passenger-1', motoristaId: 'driver-1' });
  });

  it('rejects an accept when the current ride was already taken', async () => {
    const c = chain({
      data: { id: 'ride-1', passageiro_id: 'passenger-1', motorista_id: 'driver-2', status: 'ACEITA' },
      error: null,
    });
    supabase.getUserClient.mockReturnValue(c);

    await expect(service.accept('ride-1', driver, token)).rejects.toBeInstanceOf(BadRequestException);
    expect(c.update).not.toHaveBeenCalled();
  });

  it('rejects a race where start no longer matches ACEITA + current driver', async () => {
    const c = chain({
      data: null,
      error: { message: '0 rows returned' },
    });
    supabase.getUserClient.mockReturnValue(c);
    c.maybeSingle.mockResolvedValueOnce({
      data: { id: 'ride-1', passageiro_id: 'passenger-1', motorista_id: 'driver-1', status: 'ACEITA' },
      error: null,
    });

    await expect(service.start('ride-1', driver, token)).rejects.toBeInstanceOf(BadRequestException);

    expect(c.update).toHaveBeenCalledWith({ status: 'EM_ANDAMENTO' });
    expect(c.eq).toHaveBeenCalledWith('status', 'ACEITA');
    expect(c.eq).toHaveBeenCalledWith('motorista_id', 'driver-1');
  });

  it('cancels only when the passenger and state predicate still match', async () => {
    const c = chain({
      data: { id: 'ride-1', passageiro_id: 'passenger-1', motorista_id: null, status: 'CANCELADA' },
      error: null,
    });
    supabase.getUserClient.mockReturnValue(c);
    c.maybeSingle.mockResolvedValueOnce({
      data: { id: 'ride-1', passageiro_id: 'passenger-1', motorista_id: null, status: 'SOLICITADA' },
      error: null,
    });

    await service.cancel('ride-1', passenger, token);

    expect(c.update).toHaveBeenCalledWith({ status: 'CANCELADA' });
    expect(c.eq).toHaveBeenCalledWith('passageiro_id', 'passenger-1');
    expect(c.in).toHaveBeenCalledWith('status', ['SOLICITADA', 'ACEITA']);
  });

  it('rejects cancellation by a driver', async () => {
    await expect(service.cancel('ride-1', driver, token)).rejects.toBeInstanceOf(ForbiddenException);
    expect(supabase.getUserClient).not.toHaveBeenCalled();
  });

  it('persists a ride with server-side fare, commission and payment mapping', async () => {
    const passengerProfile = chain({ data: { id: 'passenger-1' }, error: null });
    const insertResult = {
      data: { id: 'ride-1' },
      error: null,
    };
    passengerProfile.single.mockResolvedValueOnce(insertResult);
    // The service uses the same fluent client for profile lookup and insert.
    passengerProfile.insert.mockImplementation(() => passengerProfile);
    passengerProfile.select.mockImplementation(() => passengerProfile);
    passengerProfile.eq.mockImplementation(() => passengerProfile);
    passengerProfile.maybeSingle.mockResolvedValue({ data: { id: 'passenger-1' }, error: null });
    passengerProfile.single
      .mockResolvedValueOnce(insertResult);

    const client: any = {
      from: jest.fn()
        .mockReturnValueOnce(passengerProfile)
        .mockReturnValueOnce(passengerProfile),
    };
    supabase.getUserClient.mockReturnValue(client);

    const result = await service.request(
      {
        destination: 'Centro',
        category: 'confort',
        paymentMethod: 'orangeMoney',
        originLat: 12.3,
        originLng: -15.4,
        destinationLat: 12.4,
        destinationLng: -15.5,
      },
      passenger,
      token,
    );

    expect(passengerProfile.insert).toHaveBeenCalledWith(expect.objectContaining({
      passageiro_id: 'passenger-1',
      valor_total: 3500,
      valor_comissao: 700,
      forma_pagamento: 'ORANGE_MONEY',
      status: 'SOLICITADA',
    }));
    expect(result).toMatchObject({ rideId: 'ride-1', persisted: true, estimatedFare: 3500 });
  });

  it('requires both destination coordinates together', async () => {
    await expect(service.request(
      { destination: 'Centro', originLat: 12, originLng: -15, destinationLat: 12.4 },
      passenger,
      token,
    )).rejects.toBeInstanceOf(BadRequestException);
  });

  it('delegates completion and settlement to WalletService', async () => {
    wallet.completeRideSettlement.mockResolvedValue({ rideId: 'ride-1', settled: true, driverCredit: 2000 });

    const result = await service.complete('ride-1', driver);

    expect(wallet.completeRideSettlement).toHaveBeenCalledWith('ride-1', driver);
    expect(result).toEqual({ rideId: 'ride-1', settled: true, driverCredit: 2000 });
  });
});
