import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { Request } from 'express';
import { SupabaseService } from '../supabase/supabase.service';

export type AuthenticatedUser = {
  sub: string;
  email: string;
  role: 'passenger' | 'driver' | 'admin';
  sv: number;
};

export type AuthenticatedRequest = Request & { user: AuthenticatedUser };

@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(
    private readonly jwtService: JwtService,
    private readonly supabase: SupabaseService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const [type, token] = request.headers.authorization?.split(' ') ?? [];

    if (type !== 'Bearer' || !token) {
      throw new UnauthorizedException('Token de acesso não informado.');
    }

    try {
      const payload =
        await this.jwtService.verifyAsync<AuthenticatedUser>(token);

      const result = await this.supabase
        .getClient()
        .from('usuarios')
        .select('id, tipo_perfil, status_conta, session_version')
        .eq('id', payload.sub)
        .maybeSingle();

      if (
        result.error ||
        !result.data ||
        result.data.status_conta === 'BLOQUEADO' ||
        result.data.session_version !== payload.sv
      ) {
        throw new UnauthorizedException('Sessão inválida.');
      }

      const roleMap = {
        PASSAGEIRO: 'passenger',
        MOTORISTA: 'driver',
        ADMIN: 'admin',
      } as const;

      const role = roleMap[result.data.tipo_perfil as keyof typeof roleMap];
      if (!role) {
        throw new UnauthorizedException('Sessão inválida.');
      }

      request.user = {
        ...payload,
        role,
        sv: result.data.session_version,
      };
      return true;
    } catch (error) {
      if (error instanceof UnauthorizedException) throw error;
      throw new UnauthorizedException('Token inválido ou expirado.');
    }
  }
}
