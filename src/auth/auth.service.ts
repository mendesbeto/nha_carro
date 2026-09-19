import {
  ConflictException,
  Injectable,
  InternalServerErrorException,
  UnauthorizedException,
} from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';
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
  constructor(private readonly supabase: SupabaseService) {}

  async register(dto: RegisterDto): Promise<AuthResponse> {
    const email = dto.email.trim().toLowerCase();
    const name = dto.name.trim();
    const client = this.supabase.getClient();

    // Supabase Auth is the sole password store. Never write passwords or
    // password hashes to public.auth_credentials.
    const created = await client.auth.admin.createUser({
      email,
      password: dto.password,
      email_confirm: true,
      user_metadata: { full_name: name },
    });

    if (created.error || !created.data.user) {
      if (created.error?.status === 422 || created.error?.code === 'email_exists') {
        throw new ConflictException('Este e-mail já está registrado.');
      }
      throw new InternalServerErrorException(
        created.error?.message ?? 'Não foi possível criar a conta.',
      );
    }

    const authUser = created.data.user;
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
      await client.auth.admin.deleteUser(authUser.id);
      if (profile.error?.code === '23505') {
        throw new ConflictException('Este e-mail ou telefone já está registrado.');
      }
      throw new InternalServerErrorException(
        profile.error?.message ?? 'Não foi possível criar o perfil.',
      );
    }

    await this.saveVehicleIfProvided(client, dto, authUser.id);

    // Return a normal Supabase Auth session so the same JWT can be used by
    // Supabase RLS and by the NestJS API.
    const signedIn = await client.auth.signInWithPassword({ email, password: dto.password });
    if (signedIn.error || !signedIn.data.session) {
      // The account exists; the client can retry login. Do not expose the
      // service-role credential or manufacture a second JWT here.
      throw new InternalServerErrorException(
        signedIn.error?.message ?? 'Conta criada, mas não foi possível iniciar a sessão.',
      );
    }

    return this.toAuthResponse(profile.data, email, signedIn.data.session);
  }

  async login(dto: LoginDto): Promise<AuthResponse> {
    const email = dto.email.trim().toLowerCase();
    const client = this.supabase.getClient();

    const signedIn = await client.auth.signInWithPassword({
      email,
      password: dto.password,
    });

    if (signedIn.error || !signedIn.data.user || !signedIn.data.session) {
      throw new UnauthorizedException('Credenciais inválidas.');
    }

    const profile = await client
      .from('usuarios')
      .select('id, nome, telefone, tipo_perfil, status_conta')
      .eq('id', signedIn.data.user.id)
      .maybeSingle();

    if (profile.error || !profile.data) {
      throw new UnauthorizedException('Perfil de usuário não encontrado.');
    }
    if (profile.data.status_conta === 'BLOQUEADO') {
      await client.auth.admin.signOut(signedIn.data.session.access_token);
      throw new UnauthorizedException('Esta conta está bloqueada.');
    }

    return this.toAuthResponse(profile.data, signedIn.data.user.email ?? email, signedIn.data.session);
  }

  async refresh(rawRefreshToken: string): Promise<AuthResponse> {
    const client = this.supabase.getClient();
    const refreshed = await client.auth.refreshSession({
      refresh_token: rawRefreshToken,
    });

    if (refreshed.error || !refreshed.data.user || !refreshed.data.session) {
      throw new UnauthorizedException('Refresh token inválido, expirado ou revogado.');
    }

    const profile = await client
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
    const client = this.supabase.getClient();
    const refreshed = await client.auth.refreshSession({
      refresh_token: rawRefreshToken,
    });
    if (refreshed.data.user) {
      await client.auth.admin.signOut(refreshed.data.session.access_token);
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
      throw new InternalServerErrorException('Não foi possível cadastrar o veículo.');
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
