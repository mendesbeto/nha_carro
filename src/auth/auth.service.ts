import {
  ConflictException,
  Injectable,
  InternalServerErrorException,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';
import { SupabaseService } from '../supabase/supabase.service';
import { LoginDto } from './dto/login.dto';
import { RegisterDto, UserRole } from './dto/register.dto';

export type PublicUser = {
  id: string;
  name: string;
  email: string;
  role: 'passenger' | 'driver' | 'admin';
};

export type AuthResponse = PublicUser & {
  access_token: string;
};

const ROLE_TO_DATABASE: Record<
  UserRole,
  'PASSAGEIRO' | 'MOTORISTA' | 'ADMIN'
> = {
  passenger: 'PASSAGEIRO',
  driver: 'MOTORISTA',
  admin: 'ADMIN',
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
    private readonly jwtService: JwtService,
  ) {}

  async register(dto: RegisterDto): Promise<AuthResponse> {
    const email = dto.email.trim().toLowerCase();
    const name = dto.name.trim();
    const client = this.supabase.getClient();

    const existing = await client
      .from('auth_credentials')
      .select('usuario_id')
      .eq('email', email)
      .maybeSingle();
    if (existing.error && !this.isMissingTable(existing.error)) {
      throw new InternalServerErrorException(existing.error.message);
    }
    if (existing.data) {
      throw new ConflictException('Este e-mail já está registrado.');
    }

    const userResult = await client
      .from('usuarios')
      .insert({
        nome: name,
        telefone: email,
        tipo_perfil: ROLE_TO_DATABASE[dto.role],
      })
      .select('id, nome, telefone, tipo_perfil')
      .single();

    if (userResult.error || !userResult.data) {
      if (this.isDuplicateError(userResult.error)) {
        throw new ConflictException('Este e-mail já está registrado.');
      }
      throw new InternalServerErrorException(
        userResult.error?.message ?? 'Não foi possível criar o usuário.',
      );
    }

    const passwordHash = await bcrypt.hash(dto.password, 12);
    const credentialsResult = await client.from('auth_credentials').insert({
      usuario_id: userResult.data.id,
      email,
      password_hash: passwordHash,
    });

    if (credentialsResult.error) {
      await client.from('usuarios').delete().eq('id', userResult.data.id);
      if (this.isDuplicateError(credentialsResult.error)) {
        throw new ConflictException('Este e-mail já está registrado.');
      }
      throw new InternalServerErrorException(credentialsResult.error.message);
    }

    await this.saveVehicleIfProvided(client, dto, userResult.data.id);
    const user = this.toPublicUser(userResult.data);

    return {
      ...user,
      access_token: await this.createAccessToken(user),
    };
  }

  async login(dto: LoginDto): Promise<AuthResponse> {
    const email = dto.email.trim().toLowerCase();
    const client = this.supabase.getClient();
    const credentialsResult = await client
      .from('auth_credentials')
      .select('usuario_id, email, password_hash')
      .eq('email', email)
      .maybeSingle();

    if (credentialsResult.error || !credentialsResult.data) {
      throw new UnauthorizedException('Credenciais inválidas.');
    }

    const passwordMatches = await bcrypt.compare(
      dto.password,
      credentialsResult.data.password_hash,
    );
    if (!passwordMatches) {
      throw new UnauthorizedException('Credenciais inválidas.');
    }

    const userResult = await client
      .from('usuarios')
      .select('id, nome, telefone, tipo_perfil, status_conta')
      .eq('id', credentialsResult.data.usuario_id)
      .maybeSingle();
    if (userResult.error || !userResult.data) {
      throw new UnauthorizedException('Credenciais inválidas.');
    }
    if (userResult.data.status_conta === 'BLOQUEADO') {
      throw new UnauthorizedException('Esta conta está bloqueada.');
    }

    const user = this.toPublicUser(userResult.data);

    return {
      ...user,
      access_token: await this.createAccessToken(user),
    };
  }

  async getUserFromToken(payload: { sub: string; role: PublicUser['role'] }) {
    const client = this.supabase.getClient();
    const result = await client
      .from('usuarios')
      .select('id, nome, telefone, tipo_perfil, status_conta')
      .eq('id', payload.sub)
      .maybeSingle();

    if (result.error || !result.data || result.data.status_conta === 'BLOQUEADO') {
      throw new UnauthorizedException('Sessão inválida.');
    }

    return this.toPublicUser(result.data);
  }

  private createAccessToken(user: PublicUser): Promise<string> {
    return this.jwtService.signAsync({
      sub: user.id,
      email: user.email,
      role: user.role,
    });
  }

  private async saveVehicleIfProvided(
    client: ReturnType<SupabaseService['getClient']>,
    dto: RegisterDto,
    userId: string,
  ): Promise<void> {
    if (dto.role !== 'driver' || !dto.vehicle?.trim() || !dto.plate?.trim()) {
      return;
    }

    await client.from('veiculos_motoristas').insert({
      motorista_id: userId,
      placa: dto.plate.trim(),
      marca_modelo: dto.vehicle.trim(),
      cor: 'Não informada',
      categoria: 'TAXI_TRADICIONAL',
    });
  }

  private toPublicUser(user: {
    id: string;
    nome: string;
    telefone: string;
    tipo_perfil: 'PASSAGEIRO' | 'MOTORISTA' | 'ADMIN';
  }): PublicUser {
    return {
      id: user.id,
      name: user.nome,
      email: user.telefone,
      role: DATABASE_TO_ROLE[user.tipo_perfil],
    };
  }

  private isDuplicateError(error: { code?: string } | null): boolean {
    return error?.code === '23505';
  }

  private isMissingTable(error: { code?: string } | null): boolean {
    return error?.code === '42P01';
  }
}
