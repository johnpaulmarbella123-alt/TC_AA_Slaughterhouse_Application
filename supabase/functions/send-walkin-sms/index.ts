/// <reference path="../edge-runtime.d.ts" />
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";

function normalizePhPhone(raw: string): string {
  const trimmed = raw.trim();
  const digits = trimmed.replace(/\D/g, "");
  if (digits.length === 11 && digits.startsWith("09")) {
    return `+63${digits.substring(1)}`;
  }
  if (digits.length === 10 && digits.startsWith("9")) {
    return `+63${digits}`;
  }
  if (digits.length === 12 && digits.startsWith("63")) {
    return `+${digits}`;
  }
  if (trimmed.startsWith("+") && digits.length >= 10) {
    return `+${digits}`;
  }
  return digits;
}

Deno.serve(async (req: Request) => {
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // 1. Authenticate caller via Supabase JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(
        JSON.stringify({ success: false, error: "Missing or invalid authorization token" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
    const token = authHeader.replace("Bearer ", "");

    const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
    const supabaseServiceKey =
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || Deno.env.get("SUPABASE_ANON_KEY") || "";
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);
    if (authError || !user) {
      return new Response(
        JSON.stringify({ success: false, error: "Unauthorized: Invalid or expired session" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 2. Verify caller is staff (Admin, Clerk, or Inspector)
    const { data: profile } = await supabase
      .from("profiles")
      .select("role")
      .eq("id", user.id)
      .maybeSingle();

    const role = (profile?.role || "").toString().toLowerCase();
    const allowedRoles = ["admin", "clerk", "inspector", "staff", "superadmin"];
    if (!allowedRoles.includes(role)) {
      return new Response(
        JSON.stringify({ success: false, error: "Forbidden: Staff role required to send SMS" }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 3. Parse request payload
    const body = await req.json();
    const rawPhone = (body?.phone ?? "").toString().trim();
    const message = (body?.message ?? "").toString().trim();

    if (!rawPhone || !message) {
      return new Response(
        JSON.stringify({ success: false, error: "Both phone and message are required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const recipient = normalizePhPhone(rawPhone);
    if (!recipient || recipient.replace(/\D/g, "").length < 10) {
      return new Response(
        JSON.stringify({ success: false, error: "Invalid phone number format" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 4. Read TextBee credentials from Supabase secrets
    const apiKey = Deno.env.get("TEXTBEE_API_KEY") || "";
    const deviceId = Deno.env.get("TEXTBEE_DEVICE_ID") || "";

    if (!apiKey || !deviceId) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "TextBee SMS is not configured yet (set TEXTBEE_API_KEY and TEXTBEE_DEVICE_ID secrets in Supabase).",
        }),
        { status: 503, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 5. Call TextBee Gateway API
    const textBeeUrl = `https://api.textbee.dev/api/v1/gateway/devices/${encodeURIComponent(deviceId)}/send-sms`;
    const tbRes = await fetch(textBeeUrl, {
      method: "POST",
      headers: {
        "x-api-key": apiKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        recipients: [recipient],
        message,
      }),
    });

    const tbText = await tbRes.text();
    let tbData: unknown = tbText;
    try {
      tbData = JSON.parse(tbText);
    } catch {
      // keep raw text
    }

    if (!tbRes.ok) {
      return new Response(
        JSON.stringify({
          success: false,
          error: `TextBee API error (${tbRes.status})`,
          details: tbData,
        }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({
        success: true,
        recipient,
        providerResponse: tbData,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({
        success: false,
        error: err instanceof Error ? err.message : String(err),
      }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
