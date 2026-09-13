import {
  BadRequestException,
  Injectable,
  InternalServerErrorException,
} from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';
import { RequestRideDto } from './dto/request-ride.dto';

const FARES: Record<string, number> = {
  taxi: 2500,
  confort: 3500,
  moto: 1800,
};

const PAYMENT_METHODS: Record<string, 'DINHEIRO' | 'ORANGE_MONEY' | 'MTN_MONEY'> =
  {
    cash: 'DINHEIRO',
    orangeMoney: 'ORANGE_MONEY',
    mtnMoney: 'MTN_MONEY',
  };

@Injectable()
export class RidesService {
  constructor(private readonly supabase: SupabaseService) {}

  async request(dto: RequestRideDto) {
    const destination = dto.destination.trim();
    if (!destination) {
      throw new BadRequestException('Informe o destino da viagem.');
    }

    const category = dto.category ?? 'taxi';
    const paymentMethod = dto.paymentMethod ?? 'cash';
    const estimatedFare = FARES[category] ?? FARES.taxi;
    const response: {
      origin: string;
      destination: string;
      category: string;
      paymentMethod: string;
      estimatedFare: number;
      persisted: boolean;
      rideId?: string;
    } = {
      origin: 'A minha localização',
      destination,
      category,
      paymentMethod,
      estimatedFare,
      persisted: false,
    };

    const coordinatesProvided = [
      dto.originLat,
      dto.originLng,
      dto.destinationLat,
      dto.destinationLng,
    ].every((value) => value !== undefined);

    if (!coordinatesProvided || !dto.passengerId) {
      return response;
    }

    const client = this.supabase.getClient();
    const passenger = await client
      .from('usuarios')
      .select('id')
      .eq('id', dto.passengerId)
      .maybeSingle();
    if (passenger.error || !passenger.data) {
      throw new BadRequestException('Passageiro inválido.');
    }

    const result = await client
      .from('corridas')
      .insert({
        passageiro_id: dto.passengerId,
        origem_coords: {
          type: 'Point',
          coordinates: [dto.originLng, dto.originLat],
        },
        destino_coords: {
          type: 'Point',
          coordinates: [dto.destinationLng, dto.destinationLat],
        },
        valor_total: estimatedFare,
        valor_comissao: Math.round(estimatedFare * 0.2 * 100) / 100,
        forma_pagamento: PAYMENT_METHODS[paymentMethod],
        status: 'SOLICITADA',
      })
      .select('id')
      .single();

    if (result.error || !result.data) {
      throw new InternalServerErrorException(
        result.error?.message ?? 'Não foi possível solicitar a corrida.',
      );
    }

    return {
      ...response,
      persisted: true,
      rideId: result.data.id,
    };
  }
}
