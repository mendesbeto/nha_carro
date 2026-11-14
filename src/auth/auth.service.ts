import {
  ConflictException,
  Injectable,
  InternalServerErrorException,
  UnauthorizedException,
} from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';
import { EmailService } from './email.service';
import { LoginDto } from './dto/login.dto';
import { RegisterDto, RegistrationRole } from './dto/register.dto';

export type PublicUser = {
  id: string;
  name: string;
  email: string;
  role: 'passenger' | 'driver' | 'admin';
};

export type AuthResponse = PublicUser & {
  access_token: string;
  refresh_token: string;
};

const ROLE_TO_DATABASE: Record<RegistrationRole, 'PASSAGEIRO' | 'MOTORISTA'> = {
  passenger: 'PASSAGEIRO',
  driver: 'MOTORISTA',
};

const DATABASE_TO_ROLE: Record<
  'PASSAGEIRO' | 'MOTORISTA' | 'ADMIN',
  PublicUser['role']
> = {
  PASSAGEIRO: 'passenger',
  MOTORISTA: 'driver',
  ADMIN: 'admin',
};

@Injectable()
export class AuthService {
  constructor(
    private readonly supabase: SupabaseService,
    private readonly emailService: EmailService,
  ) {}

  async register(dto: RegisterDto): Promise<{ message: string; email: string }> {
    const email = dto.email.trim().toLowerCase();
    const name = dto.name.trim();
    const redirectTo = process.env.EMAIL_CONFIRMATION_REDIRECT_URL;
    if (!redirectTo) {
      throw new InternalServerErrorException(
        'A confirmação de e-mail ainda não está configurada.',
      );
    }

    const client = this.supabase.getClient();
    const generated = await client.auth.admin.generateLink({
      type: 'signup',
      email,
      password: dto.password,
      options: {
        redirectTo,
        data: { full_name: name },
      },
    });

    if (generated.error || !generated.data.user || !generated.data.properties?.action_link) {
      if (
        generated.error?.status === 422 ||
        generated.error?.code === 'email_exists' ||
        generated.error?.message?.toLowerCase().includes('already registered')
      ) {
        throw new ConflictException('Este e-mail já está registrado.');
      }
      throw new InternalServerErrorException(
        generated.error?.message ?? 'Não foi possível preparar a confirmação da conta.',
      );
    }

    const authUser = generated.data.user;
    const profile = await client
      .from('usuarios')
      .insert({
        id: authUser.id,
        nome: name,
        telefone: dto.telefone.trim(),
        tipo_perfil: ROLE_TO_DATABASE[dto.role],
      })
      .select('id, nome, telefone, tipo_perfil')
      .single();

    if (profile.error || !profile.data) {
      // Do not delete the Auth identity here: generateLink may return an existing
      // unconfirmed user. A failed profile insert must never remove that account.
      if (profile.error?.code === '23505') {
        throw new ConflictException('Este e-mail ou telefone já está registrado.');
      }
      throw new InternalServerErrorException(
        profile.error?.message ?? 'Não foi possível criar o perfil.',
      );
    }

    try {
      await this.saveVehicleIfProvided(client, dto, authUser.id);
      await this.emailService.sendSignupConfirmationEmail(
        email,
        generated.data.properties.action_link,
      );
    } catch (error) {
      // Roll back only rows created by this attempt. Keep the Auth identity because
      // its ownership cannot safely be inferred from generateLink's response.
      await client.from('veiculos_motoristas').delete().eq('motorista_id', authUser.id);
      await client.from('usuarios').delete().eq('id', authUser.id);
      throw error;
    }

    return {
      message: 'Conta criada. Verifique o seu e-mail e confirme o endereço antes de iniciar sessão.',
      email,
    };
  }

  async login(dto: LoginDto): Promise<AuthResponse> {
    const authClient = this.supabase.getAuthClient();
    const email = dto.email.trim().toLowerCase();

    const signedIn = await authClient.auth.signInWithPassword({
      email,
      password: dto.password,
    });

    if (signedIn.error || !signedIn.data.user || !signedIn.data.session) {
      if (signedIn.error?.message?.toLowerCase().includes('email not confirmed')) {
        throw new UnauthorizedException('Confirme o seu e-mail antes de iniciar sessão.');
      }
      throw new UnauthorizedException('Credenciais inválidas.');
    }

    const profile = await authClient
      .from('usuarios')
      .select('id, nome, telefone, tipo_perfil, status_conta')
      .eq('id', signedIn.data.user.id)
      .maybeSingle();

    if (profile.error || !profile.data) {
      throw new UnauthorizedException('Perfil de usuário não encontrado.');
    }
    if (profile.data.status_conta === 'BLOQUEADO') {
      await this.supabase
        .getClient()
        .auth.admin.signOut(signedIn.data.session.access_token);
      throw new UnauthorizedException('Esta conta está bloqueada.');
    }

    return this.toAuthResponse(
      profile.data,
      signedIn.data.user.email ?? email,
      signedIn.data.session,
    );
  }

  async refresh(rawRefreshToken: string): Promise<AuthResponse> {
    const authClient = this.supabase.getAuthClient();
    const refreshed = await authClient.auth.refreshSession({
      refresh_token: rawRefreshToken,
    });

    if (refreshed.error || !refreshed.data.user || !refreshed.data.session) {
      throw new UnauthorizedException('Refresh token inválido, expirado ou revogado.');
    }

    const profile = await authClient
      .from('usuarios')
      .select('id, nome, telefone, tipo_perfil, status_conta')
      .eq('id', refreshed.data.user.id)
      .maybeSingle();

    if (profile.error || !profile.data || profile.data.status_conta === 'BLOQUEADO') {
      throw new UnauthorizedException('Sessão inválida.');
    }

    return this.toAuthResponse(
      profile.data,
      refreshed.data.user.email ?? '',
      refreshed.data.session,
    );
  }

  async logout(rawRefreshToken: string): Promise<void> {
    const authClient = this.supabase.getAuthClient();
    const refreshed = await authClient.auth.refreshSession({
      refresh_token: rawRefreshToken,
    });

    if (refreshed.error || !refreshed.data.user || !refreshed.data.session) {
      return;
    }

    const signedOut = await authClient.auth.signOut({ scope: 'local' });

    if (signedOut.error) {
      throw new InternalServerErrorException(
        signedOut.error.message ?? 'Não foi possível encerrar a sessão.',
      );
    }
  }

  async getUserFromToken(payload: { sub: string; email: string; role: PublicUser['role'] }) {
    const client = this.supabase.getClient();
    const result = await client
      .from('usuarios')
      .select('id, nome, telefone, tipo_perfil, status_conta')
      .eq('id', payload.sub)
      .maybeSingle();

    if (result.error || !result.data || result.data.status_conta === 'BLOQUEADO') {
      throw new UnauthorizedException('Sessão inválida.');
    }

    return this.toPublicUser(result.data, payload.email);
  }

  private async saveVehicleIfProvided(
    client: ReturnType<SupabaseService['getClient']>,
    dto: RegisterDto,
    userId: string,
  ): Promise<void> {
    if (dto.role !== 'driver' || !dto.vehicle?.trim() || !dto.plate?.trim()) {
      return;
    }

    const result = await client.from('veiculos_motoristas').insert({
      motorista_id: userId,
      placa: dto.plate.trim(),
      marca_modelo: dto.vehicle.trim(),
      cor: 'Não informada',
      categoria: 'TAXI_TRADICIONAL',
    });

    if (result.error) {
      throw new InternalServerErrorException(
        'Não foi possível cadastrar o veículo.',
      );
    }
  }

  private toAuthResponse(
    user: {
      id: string;
      nome: string;
      telefone: string;
      tipo_perfil: 'PASSAGEIRO' | 'MOTORISTA' | 'ADMIN';
    },
    email: string,
    session: { access_token: string; refresh_token: string },
  ): AuthResponse {
    return {
      ...this.toPublicUser(user, email),
      access_token: session.access_token,
      refresh_token: session.refresh_token,
    };
  }

  private toPublicUser(
    user: {
      id: string;
      nome: string;
      telefone: string;
      tipo_perfil: 'PASSAGEIRO' | 'MOTORISTA' | 'ADMIN';
    },
    email: string,
  ): PublicUser {
    return {
      id: user.id,
      name: user.nome,
      email,
      role: DATABASE_TO_ROLE[user.tipo_perfil],
    };
  }
}
