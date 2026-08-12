// supabase/functions/admin-create-user/index.ts
//
// Creates a new login account (auth.users) plus a matching
// user_profiles row. Only callable by someone whose OWN profile has
// role = 'admin' — checked server-side here, never trusted from the
// client. This must run as an Edge Function (not client-side JS)
// because creating auth users requires the service_role key, which
// must never be shipped to the browser.
//
// Deploy with:
//   supabase functions deploy admin-create-user
//
// No manual secrets needed — SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY
// are automatically available to every Edge Function.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return json({ error: "Missing Authorization header" }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const anonKey     = Deno.env.get("SUPABASE_ANON_KEY")!;

    // Client scoped to the CALLER's own JWT — used only to verify who's calling
    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user: caller }, error: callerErr } = await callerClient.auth.getUser();
    if (callerErr || !caller) {
      return json({ error: "Invalid session" }, 401);
    }

    // Privileged client — bypasses RLS, only used after admin check passes
    const adminClient = createClient(supabaseUrl, serviceKey);

    const { data: callerProfile, error: profileErr } = await adminClient
      .from("user_profiles")
      .select("role")
      .eq("id", caller.id)
      .single();

    if (profileErr || !callerProfile || callerProfile.role !== "admin") {
      return json({ error: "Only an admin can create accounts" }, 403);
    }

    const body = await req.json();
    const { email, password, display_name, role, team_id } = body;

    if (!email || !password || !display_name || !role) {
      return json({ error: "email, password, display_name, and role are required" }, 400);
    }
    if (!["admin", "leader", "member"].includes(role)) {
      return json({ error: "role must be admin, leader, or member" }, 400);
    }
    if (password.length < 6) {
      return json({ error: "Password must be at least 6 characters" }, 400);
    }

    // Create the login account
    const { data: created, error: createErr } = await adminClient.auth.admin.createUser({
      email,
      password,
      email_confirm: true, // skip the confirmation email — admin is vouching for this account
    });
    if (createErr || !created?.user) {
      return json({ error: createErr?.message || "Failed to create account" }, 400);
    }

    // Create the matching profile row
    const { error: insertErr } = await adminClient.from("user_profiles").insert({
      id: created.user.id,
      display_name,
      role,
      team_id: team_id || null,
    });
    if (insertErr) {
      // Roll back the auth user so we don't leave an orphaned login with no profile
      await adminClient.auth.admin.deleteUser(created.user.id);
      return json({ error: "Failed to create profile: " + insertErr.message }, 400);
    }

    return json({ success: true, user_id: created.user.id }, 200);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
