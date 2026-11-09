// The service-role client and the signed-in player behind a request.
//
// The functions write foods and scans with the service role, so they must check who is
// calling themselves rather than rely on row-level security.

import {
  createClient,
  type SupabaseClient,
} from "npm:@supabase/supabase-js@2.118.0";
import { HttpError } from "./http.ts";

let client: SupabaseClient | undefined;

export function admin(): SupabaseClient {
  if (!client) {
    const url = Deno.env.get("SUPABASE_URL");
    const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !key) {
      throw new Error("SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY is missing");
    }
    client = createClient(url, key, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
  }
  return client;
}

/** Returns the player's id, or throws a 401 the app shows as "log in again". */
export async function requireUser(req: Request): Promise<string> {
  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "")
    .trim();
  if (!token) throw signedOut();
  const { data, error } = await admin().auth.getUser(token);
  if (error || !data.user) throw signedOut();
  return data.user.id;
}

function signedOut(): HttpError {
  return new HttpError(401, "signed_out", "Log in again to use this.");
}
