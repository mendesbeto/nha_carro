import {
  Injectable,
  ServiceUnavailableException,
} from '@nestjs/common';
import { createClient, SupabaseClient } from '@supabase/supabase-js';

@Injectable()
export class SupabaseService {
  private readonly adminClient: SupabaseClient | null;
  private readonly authUrl: string | undefined;
  private readonly authKey: string | undefined;

  constructor() {
    const url = process.env.SUPABASE_URL;
    const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
    const publishableKey =
      process.env.SUPABASE_PUBLISHABLE_KEY ?? process.env.SUPABASE_ANON_KEY;

    this.authUrl = url;
    this.authKey = publishableKey;
    this.adminClient =
      url && serviceRoleKey
        ? createClient(url, serviceRoleKey, {
            auth: {
              autoRefreshToken: false,
              persistSession: false,
              detectSessionInUrl: false,
            },
          })
        : null;
  }

  isConfigured(): boolean {
    return this.adminClient !== null;
  }

  getClient(): SupabaseClient {
    if (!this.adminClient) {
      throw new ServiceUnavailableException(
        'Supabase não está configurado no servidor.',
      );
    }
    return this.adminClient;
  }

  getAuthClient(): SupabaseClient {
    if (!this.authUrl || !this.authKey) {
      throw new ServiceUnavailableException(
        'Supabase Auth não está configurado no servidor.',
      );
    }

    // Each operation gets an isolated client. signInWithPassword() and
    // refreshSession() mutate the client's in-memory session; sharing one
    // client between concurrent users could otherwise mix Authorization
    // headers across requests.
    return createClient(this.authUrl, this.authKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUrl: false,
      },
    });
  }
}
