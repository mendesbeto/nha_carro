import { BadRequestException, Injectable, ServiceUnavailableException, UnauthorizedException } from '@nestjs/common';
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

  async createTopUp(
    body: { amount?: number; method?: 'orangeMoney' | 'mtnMoney'; idempotencyKey?: string },
    user: CurrentUserPayload,
    _accessToken: string,
  ) {
    const amount = Number(body.amount);
    if (!Number.isFinite(amount) || amount <= 0 || amount > 100000) {
      throw new BadRequestException('A recarga deve estar entre 1 e 100.000 CFA.');
    }

    const method =
      body.method === 'mtnMoney' ? 'MTN_MONEY' :
      body.method === 'orangeMoney' ? 'ORANGE_MONEY' : null;

    if (!method) {
      throw new BadRequestException('Método de pagamento inválido.');
    }

    const idempotencyKey = body.idempotencyKey?.trim();
    if (!idempotencyKey || idempotencyKey.length > 120) {
      throw new BadRequestException('Chave de idempotência obrigatória.');
    }

    // Payment records are created by the trusted backend, never directly by
    // the mobile client. The authenticated JWT has already been validated by
    // JwtAuthGuard and user.sub is the authoritative account id.
    const admin = this.supabase.getClient();

    const existing = await admin
      .from('recargas_carteira')
      .select('id, valor, metodo, status, referencia_provedor, checkout_url, criado_em')
      .eq('usuario_id', user.sub)
      .eq('chave_idempotencia', idempotencyKey)
      .maybeSingle();

    if (existing.error) {
      throw new BadRequestException(existing.error.message);
    }

    if (existing.data) {
      return { ...existing.data, reused: true };
    }

    const created = await admin
      .from('recargas_carteira')
      .insert({
        usuario_id: user.sub,
        valor: amount.toFixed(2),
        metodo: method,
        status: 'PENDENTE',
        chave_idempotencia: idempotencyKey,
      })
      .select('id, valor, metodo, status, referencia_provedor, checkout_url, criado_em')
      .single();

    if (created.error || !created.data) {
      // A concurrent request with the same idempotency key may have won the
      // unique race. Return that record instead of creating a second charge.
      const raced = await admin
        .from('recargas_carteira')
        .select('id, valor, metodo, status, referencia_provedor, checkout_url, criado_em')
        .eq('usuario_id', user.sub)
        .eq('chave_idempotencia', idempotencyKey)
        .maybeSingle();

      if (raced.data) {
        return { ...raced.data, reused: true };
      }

      throw new BadRequestException(
        created.error?.message ?? 'Não foi possível criar a recarga.',
      );
    }

    return { ...created.data, reused: false };
  }

  async handleWebhook(
    provider: string,
    secret: string | undefined,
    body: {
      eventId?: string;
      topupId?: string;
      providerReference?: string;
      status?: 'CONFIRMED' | 'FAILED' | 'PENDING';
      amount?: number | string;
      payload?: unknown;
    },
  ) {
    const configuredSecret = process.env.WALLET_WEBHOOK_SECRET?.trim();
    if (!configuredSecret) {
      throw new ServiceUnavailableException(
        'Webhook de pagamento ainda não está configurado.',
      );
    }

    if (!secret || secret !== configuredSecret) {
      throw new UnauthorizedException('Webhook não autorizado.');
    }

    const normalizedProvider = provider.trim().toUpperCase().replace(/-/g, '_');
    if (!['ORANGE_MONEY', 'MTN_MONEY'].includes(normalizedProvider)) {
      throw new BadRequestException('Provedor de pagamento inválido.');
    }

    const status = body.status;
    if (!status) {
      throw new BadRequestException('Status do webhook obrigatório.');
    }

    const admin = this.supabase.getClient();
    let query = admin
      .from('recargas_carteira')
      .select('id, usuario_id, valor, metodo, status, referencia_provedor')
      .limit(1);

    if (body.topupId?.trim()) {
      query = query.eq('id', body.topupId.trim());
    } else if (body.providerReference?.trim()) {
      query = query.eq('referencia_provedor', body.providerReference.trim());
    } else {
      throw new BadRequestException(
        'topupId ou providerReference é obrigatório.',
      );
    }

    const lookup = await query.maybeSingle();
    if (lookup.error) {
      throw new BadRequestException(lookup.error.message);
    }
    if (!lookup.data) {
      throw new BadRequestException('Recarga não encontrada.');
    }

    if (lookup.data.metodo !== normalizedProvider) {
      throw new BadRequestException('Provedor incompatível com a recarga.');
    }

    if (status === 'PENDING') {
      if (lookup.data.status === 'PENDENTE') {
        await admin
          .from('recargas_carteira')
          .update({ status: 'PROCESSANDO' })
          .eq('id', lookup.data.id)
          .in('status', ['PENDENTE', 'PROCESSANDO']);
      }
      return {
        accepted: true,
        status: 'PROCESSANDO',
        topupId: lookup.data.id,
      };
    }

    if (status === 'FAILED') {
      if (lookup.data.status !== 'CONFIRMADA') {
        const failed = await admin
          .from('recargas_carteira')
          .update({
            status: 'FALHOU',
            referencia_provedor:
              body.providerReference?.trim() ||
              lookup.data.referencia_provedor ||
              null,
            resposta_provedor: body.payload ?? body,
          })
          .eq('id', lookup.data.id)
          .in('status', ['PENDENTE', 'PROCESSANDO']);

        if (failed.error) {
          throw new BadRequestException(failed.error.message);
        }
      }

      return {
        accepted: true,
        status: lookup.data.status === 'CONFIRMADA' ? 'CONFIRMADA' : 'FALHOU',
        topupId: lookup.data.id,
      };
    }

    const providerReference =
      body.providerReference?.trim() || lookup.data.referencia_provedor?.trim();

    if (!providerReference) {
      throw new BadRequestException(
        'providerReference é obrigatório para confirmar a recarga.',
      );
    }

    const amount = Number(body.amount);
    if (!Number.isFinite(amount) || amount <= 0) {
      throw new BadRequestException(
        'Valor confirmado pelo provedor é obrigatório.',
      );
    }

    const confirmed = await admin.rpc('confirm_wallet_top_up', {
      p_topup_id: lookup.data.id,
      p_provider_reference: providerReference,
      p_amount: amount,
      p_provider_response: body.payload ?? body,
    });

    if (confirmed.error || !confirmed.data?.[0]) {
      throw new BadRequestException(
        confirmed.error?.message ?? 'Não foi possível confirmar a recarga.',
      );
    }

    const result = confirmed.data[0];
    return {
      accepted: true,
      topupId: result.topup_id,
      status: result.status,
      balance: result.balance,
      transactionId: result.transaction_id,
      alreadyConfirmed: result.already_confirmed,
      eventId: body.eventId ?? null,
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
