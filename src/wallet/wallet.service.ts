import { BadRequestException, Injectable, ServiceUnavailableException } from '@nestjs/common';
import { CurrentUserPayload } from '../auth/current-user.decorator';
import { SupabaseService } from '../supabase/supabase.service';

@Injectable()
export class WalletService {
  constructor(private readonly supabase: SupabaseService) {}

  async getWallet(user: CurrentUserPayload, accessToken: string) {
    const client = this.supabase.getUserClient(accessToken);

    const profile = await client
      .from('usuarios')
      .select('saldo_carteira')
      .eq('id', user.sub)
      .single();

    if (profile.error || !profile.data) {
      throw new BadRequestException('Carteira do usuário não encontrada.');
    }

    const transactions = await client
      .from('transacoes_carteira')
      .select('id, valor, tipo, referencia_provedor, criado_em')
      .eq('usuario_id', user.sub)
      .order('criado_em', { ascending: false });

    if (transactions.error) {
      throw new BadRequestException(
        transactions.error.message ?? 'Não foi possível carregar as transações.',
      );
    }

    return {
      balance: profile.data.saldo_carteira,
      transactions: transactions.data ?? [],
      testMode: process.env.WALLET_TEST_MODE === 'true',
    };
  }

  async testTopUp(
    body: { amount?: number; method?: 'orangeMoney' | 'mtnMoney' },
    user: CurrentUserPayload,
  ) {
    if (process.env.WALLET_TEST_MODE !== 'true') {
      throw new ServiceUnavailableException(
        'Recarga de teste desativada. Use uma integração de pagamento real.',
      );
    }

    const amount = Number(body.amount);
    if (!Number.isFinite(amount) || amount <= 0 || amount > 10000) {
      throw new BadRequestException(
        'A recarga de teste deve estar entre 1 e 10.000 CFA.',
      );
    }

    const type =
      body.method === 'mtnMoney' ? 'RECARGA_MTN' : 'RECARGA_ORANGE';

    const result = await this.supabase
      .getClient()
      .rpc('test_top_up_wallet', {
        p_user_id: user.sub,
        p_amount: amount,
        p_type: type,
      });

    if (result.error || !result.data?.[0]) {
      throw new BadRequestException(
        result.error?.message ?? 'Não foi possível realizar a recarga de teste.',
      );
    }

    const topUp = result.data[0];
    return {
      balance: topUp.balance,
      amount: topUp.amount,
      type: topUp.type,
      transactionId: topUp.transaction_id,
      reference: topUp.reference,
      testMode: true,
    };
  }

  async completeRideSettlement(
    rideId: string,
    user: CurrentUserPayload,
  ) {
    if (user.role !== 'driver') {
      throw new BadRequestException(
        'Apenas motoristas podem concluir e liquidar viagens.',
      );
    }

    const result = await this.supabase
      .getClient()
      .rpc('complete_ride_and_settle_wallet', {
        p_ride_id: rideId,
        p_actor_id: user.sub,
      });

    if (result.error || !result.data?.[0]) {
      throw new BadRequestException(
        result.error?.message ??
          'Não foi possível concluir e liquidar a viagem.',
      );
    }

    const settlement = result.data[0];

    return {
      rideId: settlement.ride_id,
      status: settlement.status,
      settled: settlement.settled,
      amount: settlement.amount,
      balance: settlement.balance,
      transactionId: settlement.transaction_id,
      reason: settlement.reason,
      commission: settlement.commission,
      driverCredit: settlement.driver_credit,
      driverBalance: settlement.driver_balance,
      driverTransactionId: settlement.driver_transaction_id,
    };
  }
}
