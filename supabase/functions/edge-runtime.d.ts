// Ambient declarations for Supabase Edge Runtime (Deno) in VS Code TypeScript Server
declare namespace Deno {
  export interface Env {
    get(key: string): string | undefined;
    set(key: string, value: string): void;
    delete(key: string): void;
    has(key: string): boolean;
    toObject(): Record<string, string>;
  }
  export const env: Env;
  export function serve(
    handler: (req: Request) => Response | Promise<Response>
  ): void;
}

declare module "https://esm.sh/@supabase/supabase-js@2.39.8" {
  export interface SupabaseAuthClient {
    getUser(jwt?: string): Promise<{
      data: { user: { id: string; email?: string; [key: string]: any } | null };
      error: any;
    }>;
  }

  export interface SupabaseClient {
    auth: SupabaseAuthClient;
    from(table: string): any;
  }

  export function createClient(
    supabaseUrl: string,
    supabaseKey: string,
    options?: Record<string, unknown>
  ): SupabaseClient;
}

