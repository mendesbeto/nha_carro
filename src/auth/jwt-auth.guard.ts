import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { Request } from 'express';
import { SupabaseService } from '../supabase/supabase.service';

export type AuthenticatedUser = {
  sub: string;
  email: string;
  role: 'passenger' | 'driver' | 'admin';
};

export type AuthenticatedRequest = Request & { user: AuthenticatedUser };

@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(private readonly supabase: SupabaseService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const [type, token] = request.headers.authorization?.split(' ') ?? [];

    if (type !== 'Bearer' || !token) {
      throw new UnauthorizedException('Token de acesso não informado.');
    }

    try {
      const authClient = this.supabase.getAuthClient();
      const authResult = await authClient.auth.getUser(token);
      const authUser = authResult.data.user;
      if (authResult.error || !authUser) {
        throw new UnauthorizedException('Token inválido ou expirado.');
      }

      const profile = await authClient
        .from('usuarios')
        .select('id, tipo_perfil, status_conta')
        .eq('id', authUser.id)
        .maybeSingle();

      if (profile.error || !profile.data || profile.data.status_conta === 'BLOQUEADO') {
        throw new UnauthorizedException('Sessão inválida.');
      }

      const roleMap = {
        PASSAGEIRO: 'passenger',
        MOTORISTA: 'driver',
        ADMIN: 'admin',
      } as const;
      const role = roleMap[profile.data.tipo_perfil as keyof typeof roleMap];
      if (!role) {
        throw new UnauthorizedException('Sessão inválida.');
      }

      request.user = {
        sub: authUser.id,
        email: authUser.email ?? '',
        role,
      };
      return true;
    } catch (error) {
      if (error instanceof UnauthorizedException) throw error;
      throw new UnauthorizedException('Token inválido ou expirado.');
    }
  }
}
