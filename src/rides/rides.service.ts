import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  InternalServerErrorException,
} from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';
import { RequestRideDto } from './dto/request-ride.dto';
import { CurrentUserPayload } from '../auth/current-user.decorator';
import { WalletService } from '../wallet/wallet.service';

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
  constructor(
    private readonly supabase: SupabaseService,
    private readonly walletService: WalletService,
  ) {}


  async setDriverAvailability(
    body: { online: boolean; latitude?: number; longitude?: number },
    user: CurrentUserPayload,
    accessToken: string,
  ) {
    if (user.role !== 'driver') {
      throw new ForbiddenException('Apenas motoristas podem alterar a disponibilidade.');
    }

    const online = Boolean(body.online);
    const latitude = body.latitude;
    const longitude = body.longitude;

    if (online && (typeof latitude !== 'number' || typeof longitude !== 'number')) {
      throw new BadRequestException(
        'A localização do motorista é necessária para ficar online.',
      );
    }

    if (
      online &&
      (latitude! < -90 || latitude! > 90 || longitude! < -180 || longitude! > 180)
    ) {
      throw new BadRequestException('Coordenadas de localização inválidas.');
    }

    const client = this.supabase.getUserClient(accessToken);
    const existing = await client
      .from('posicoes_motoristas')
      .select('motorista_id')
      .eq('motorista_id', user.sub)
      .maybeSingle();

    if (existing.error) {
      throw new BadRequestException(existing.error.message);
    }

    const payload: Record<string, unknown> = {
      disponivel: online,
      ultima_atualizacao: new Date().toISOString(),
    };

    if (online) {
      payload.coordenadas = {
        type: 'Point',
        coordinates: [longitude, latitude],
      };
    } else if (!existing.data) {
      throw new BadRequestException(
        'Não é possível ficar offline antes de existir uma posição do motorista.',
      );
    }

    const result = existing.data
      ? await client
          .from('posicoes_motoristas')
          .update(payload)
          .eq('motorista_id', user.sub)
          .select('motorista_id, disponivel, ultima_atualizacao')
          .single()
      : await client
          .from('posicoes_motoristas')
          .insert({
            motorista_id: user.sub,
            coordenadas: payload.coordenadas,
            disponivel: true,
            ultima_atualizacao: payload.ultima_atualizacao,
          })
          .select('motorista_id, disponivel, ultima_atualizacao')
          .single();

    if (result.error || !result.data) {
      throw new BadRequestException(
        result.error?.message ?? 'Não foi possível atualizar a disponibilidade.',
      );
    }

    return {
      motoristaId: result.data.motorista_id,
      online: result.data.disponivel,
      ultimaAtualizacao: result.data.ultima_atualizacao,
    };
  }

  async available(
    user: CurrentUserPayload,
    accessToken: string,
  ) {
    if (user.role !== 'driver') {
      throw new ForbiddenException(
        'Apenas motoristas podem consultar viagens disponíveis.',
      );
    }

    const client = this.supabase.getUserClient(accessToken);
    const result = await client
      .from('corridas')
      .select(
        'id, passageiro_id, origem_coords, destino_coords, valor_total, forma_pagamento, status, criado_em',
      )
      .eq('status', 'SOLICITADA')
      .is('motorista_id', null)
      .order('criado_em', { ascending: true });

    if (result.error) {
      throw new BadRequestException(
        result.error.message ??
            'Não foi possível carregar as viagens disponíveis.',
      );
    }

    return {
      rides: (result.data ?? []).map((ride) => ({
        rideId: ride.id,
        passageiroId: ride.passageiro_id,
        origem: ride.origem_coords,
        destino: ride.destino_coords,
        valor: ride.valor_total,
        formaPagamento: ride.forma_pagamento,
        status: ride.status,
        criadoEm: ride.criado_em,
      })),
    };
  }

  async get(
    rideId: string,
    user: CurrentUserPayload,
    accessToken: string,
  ) {
    const client = this.supabase.getUserClient(accessToken);
    const result = await client
      .from('corridas')
      .select('id, passageiro_id, motorista_id, origem_coords, destino_coords, valor_total, forma_pagamento, status, criado_em')
      .eq('id', rideId)
      .maybeSingle();

    if (result.error || !result.data) {
      throw new BadRequestException('Corrida não encontrada.');
    }

    const ride = result.data;
    if (ride.passageiro_id !== user.sub && ride.motorista_id !== user.sub && user.role !== 'admin') {
      throw new ForbiddenException('Você não tem acesso a esta corrida.');
    }

    return {
      rideId: ride.id,
      passageiroId: ride.passageiro_id,
      motoristaId: ride.motorista_id,
      origem: ride.origem_coords,
      destino: ride.destino_coords,
      valor: ride.valor_total,
      formaPagamento: ride.forma_pagamento,
      status: ride.status,
      criadoEm: ride.criado_em,
    };
  }

  async accept(
    rideId: string,
    user: CurrentUserPayload,
    accessToken: string,
  ) {
    if (user.role !== 'driver') {
      throw new ForbiddenException('Apenas motoristas podem aceitar viagens.');
    }

    return this.transition(rideId, user, accessToken, {
      status: 'ACEITA',
      motorista_id: user.sub,
    });
  }

  async start(
    rideId: string,
    user: CurrentUserPayload,
    accessToken: string,
  ) {
    if (user.role !== 'driver') {
      throw new ForbiddenException('Apenas motoristas podem iniciar viagens.');
    }

    return this.transition(rideId, user, accessToken, {
      status: 'EM_ANDAMENTO',
    });
  }

  async complete(
    rideId: string,
    user: CurrentUserPayload,
  ) {
    if (user.role !== 'driver') {
      throw new ForbiddenException('Apenas motoristas podem concluir viagens.');
    }

    return this.walletService.completeRideSettlement(rideId, user);
  }

  async cancel(
    rideId: string,
    user: CurrentUserPayload,
    accessToken: string,
  ) {
    if (user.role !== 'passenger') {
      throw new ForbiddenException('Apenas passageiros podem cancelar viagens.');
    }

    return this.transition(rideId, user, accessToken, {
      status: 'CANCELADA',
    });
  }

  private async transition(
    rideId: string,
    user: CurrentUserPayload,
    accessToken: string,
    changes: {
      status: 'ACEITA' | 'EM_ANDAMENTO' | 'CANCELADA';
      motorista_id?: string;
    },
  ) {
    const client = this.supabase.getUserClient(accessToken);

    const current = await client
      .from('corridas')
      .select('id, passageiro_id, motorista_id, status')
      .eq('id', rideId)
      .maybeSingle();

    if (current.error || !current.data) {
      throw new BadRequestException('Corrida não encontrada.');
    }

    const ride = current.data;

    const isPassenger = ride.passageiro_id === user.sub;
    const isDriver = ride.motorista_id === user.sub;

    if (changes.status === 'ACEITA') {
      if (ride.status !== 'SOLICITADA' || ride.motorista_id !== null) {
        throw new BadRequestException('Esta corrida já não está disponível.');
      }
    } else if (changes.status === 'CANCELADA') {
      if (!isPassenger || !['SOLICITADA', 'ACEITA'].includes(ride.status)) {
        throw new ForbiddenException('A corrida não pode ser cancelada por este usuário.');
      }
    } else {
      if (!isDriver) {
        throw new ForbiddenException('Motorista não autorizado para esta corrida.');
      }

      const expectedPrevious =
        changes.status === 'EM_ANDAMENTO' ? 'ACEITA' : 'EM_ANDAMENTO';

      if (ride.status !== expectedPrevious) {
        throw new BadRequestException('Transição de estado inválida.');
      }
    }

    let updateQuery = client
      .from('corridas')
      .update(changes)
      .eq('id', rideId);

    if (changes.status === 'ACEITA') {
      updateQuery = updateQuery.eq('status', 'SOLICITADA').is('motorista_id', null);
    } else if (changes.status === 'EM_ANDAMENTO') {
      updateQuery = updateQuery.eq('status', 'ACEITA').eq('motorista_id', user.sub);
    } else {
      updateQuery = updateQuery
        .eq('passageiro_id', user.sub)
        .in('status', ['SOLICITADA', 'ACEITA']);
    }

    const result = await updateQuery
      .select('id, passageiro_id, motorista_id, status')
      .single();

    if (result.error || !result.data) {
      throw new BadRequestException(
        result.error?.message ?? 'Não foi possível atualizar a corrida.',
      );
    }

    return {
      rideId: result.data.id,
      status: result.data.status,
      passageiroId: result.data.passageiro_id,
      motoristaId: result.data.motorista_id,
    };
  }

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