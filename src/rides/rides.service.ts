import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  InternalServerErrorException,
} from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';
import { RequestRideDto } from './dto/request-ride.dto';
import { CurrentUserPayload } from '../auth/current-user.decorator';

const FARES: Record<string, number> = {
  taxi: 2500,
  confort: 3500,
  moto: 1800,
};

const PAYMENT_METHODS: Record<string, 'DINHEIRO' | 'ORANGE_MONEY' | 'MTN_MONEY'> = {
  cash: 'DINHEIRO',
  orangeMoney: 'ORANGE_MONEY',
  mtnMoney: 'MTN_MONEY',
};

@Injectable()
export class RidesService {
  constructor(private readonly supabase: SupabaseService) {}

  async request(
    dto: RequestRideDto,
    user: CurrentUserPayload,
    accessToken: string,
  ) {
    if (user.role !== 'passenger') {
      throw new ForbiddenException('Apenas passageiros podem solicitar viagens.');
    }

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

    const originProvided =
      dto.originLat !== undefined && dto.originLng !== undefined;

    if (!originProvided) {
      throw new BadRequestException(
        'Não foi possível determinar a localização de origem da viagem.',
      );
    }

    const destinationProvided =
      dto.destinationLat !== undefined && dto.destinationLng !== undefined;

    if (
      (dto.destinationLat !== undefined) !==
      (dto.destinationLng !== undefined)
    ) {
      throw new BadRequestException(
        'As coordenadas de destino devem ser informadas em conjunto.',
      );
    }

    const client = this.supabase.getUserClient(accessToken);
    const passenger = await client
      .from('usuarios')
      .select('id')
      .eq('id', user.sub)
      .maybeSingle();

    if (passenger.error || !passenger.data) {
      throw new BadRequestException('Passageiro inválido.');
    }

    const result = await client
      .from('corridas')
      .insert({
        passageiro_id: user.sub,
        origem_coords: {
          type: 'Point',
          coordinates: [dto.originLng, dto.originLat],
        },
        destino_coords: destinationProvided
          ? {
              type: 'Point',
              coordinates: [dto.destinationLng, dto.destinationLat],
            }
          : null,
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