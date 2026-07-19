import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

/// Service-role client. Bypasses RLS — only ever used inside Edge Functions,
/// never shipped to the client. `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`
/// are injected automatically into the function runtime by Supabase.
export function admin(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  return createClient(url, serviceKey, {
    auth: { persistSession: false },
  });
}
