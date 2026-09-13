import { Controller, Get } from '@nestjs/common';
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
}
