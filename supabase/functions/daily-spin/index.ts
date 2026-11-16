import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return new Response(JSON.stringify({ error: "Method not allowed" }), { status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" } });

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    if (!url || !serviceKey || !anonKey) throw new Error("Server configuration is incomplete.");

    const authHeader = req.headers.get("Authorization") || "";
    const token = authHeader.replace(/^Bearer\s+/i, "");
    if (!token) return new Response(JSON.stringify({ error: "Sign-in required." }), { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } });

    const authClient = createClient(url, anonKey, { global: { headers: { Authorization: `Bearer ${token}` } }, auth: { persistSession: false } });
    const { data: userData, error: authError } = await authClient.auth.getUser(token);
    if (authError || !userData.user) return new Response(JSON.stringify({ error: "Invalid session." }), { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } });

    const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
    const { data, error } = await admin.rpc("halo_claim_daily_spin", { p_user_id: userData.user.id });
    if (error) {
      const already = String(error.message || "").includes("DAILY_SPIN_ALREADY_CLAIMED");
      return new Response(JSON.stringify({ error: already ? "ئەمڕۆ پاداشتت وەرگرتووە؛ سبەی دووبارە هەوڵ بدەوە." : "نەتوانرا پاداشت وەربگیرێت." }), { status: already ? 409 : 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }
    return new Response(JSON.stringify(data), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  } catch (_error) {
    return new Response(JSON.stringify({ error: "هەڵەی سێرڤەر ڕوویدا." }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }
});
