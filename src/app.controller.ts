import { Controller, Get, ServiceUnavailableException } from '@nestjs/common';
import { SupabaseService } from './supabase/supabase.service';

@Controller('api')
export class AppController {
  constructor(private readonly supabase: SupabaseService) {}

  @Get('health')
  health(): { status: string; supabaseConfigured: boolean } {
    return {
      status: 'ok',
      supabaseConfigured: this.supabase.isConfigured(),
    };
  }

  @Get('health/ready')
  async readiness(): Promise<{ status: string; supabase: string }> {
    if (!this.supabase.isConfigured()) {
      throw new ServiceUnavailableException({
        status: 'not_ready',
        supabase: 'not_configured',
      });
    }

    const { error } = await this.supabase
      .getClient()
      .from('usuarios')
      .select('id')
      .limit(1);

    if (error) {
      throw new ServiceUnavailableException({
        status: 'not_ready',
        supabase: 'unavailable',
      });
    }

    return {
      status: 'ready',
      supabase: 'ok',
    };
  }
}
