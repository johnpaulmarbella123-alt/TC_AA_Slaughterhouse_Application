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

function normalizePhPhoneForSemaphore(e164Phone: string): string {
  const digits = e164Phone.replace(/\D/g, "");
  if (digits.length === 12 && digits.startsWith("639")) {
    return `0${digits.substring(2)}`;
  }
  if (digits.length === 11 && digits.startsWith("09")) {
    return digits;
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

    // 4. Determine SMS provider (Semaphore primary if configured, else TextBee fallback)
    const forcedProvider = (Deno.env.get("SMS_PROVIDER") || "").trim().toLowerCase();
    const semaphoreApiKey = (Deno.env.get("SEMAPHORE_API_KEY") || "").trim();
    const rawSenderName = (Deno.env.get("SEMAPHORE_SENDER_NAME") || "").trim();
    const textBeeApiKey = (Deno.env.get("TEXTBEE_API_KEY") || "").trim();
    const textBeeDeviceId = (Deno.env.get("TEXTBEE_DEVICE_ID") || "").trim();

    const useSemaphore =
      forcedProvider === "semaphore" ||
      (forcedProvider !== "textbee" && semaphoreApiKey.length > 0);

    if (useSemaphore) {
      if (!semaphoreApiKey) {
        return new Response(
          JSON.stringify({
            success: false,
            error: "Semaphore SMS is selected, but SEMAPHORE_API_KEY secret is missing in Supabase.",
          }),
          { status: 503, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      if (rawSenderName.length > 11) {
        return new Response(
          JSON.stringify({
            success: false,
            error: `SEMAPHORE_SENDER_NAME ("${rawSenderName}") exceeds the 11-character Philippine telco limit.`,
          }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const semaphoreNumber = normalizePhPhoneForSemaphore(recipient);
      const semaphorePayload: Record<string, string> = {
        apikey: semaphoreApiKey,
        number: semaphoreNumber,
        message,
      };
      if (rawSenderName.length > 0) {
        semaphorePayload.sendername = rawSenderName;
      }

      const semRes = await fetch("https://api.semaphore.co/api/v4/messages", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify(semaphorePayload),
      });

      const semText = await semRes.text();
      let semData: unknown = semText;
      try {
        semData = JSON.parse(semText);
      } catch {
        // keep raw text
      }

      if (!semRes.ok) {
        return new Response(
          JSON.stringify({
            success: false,
            provider: "semaphore",
            error: `Semaphore API error (${semRes.status})`,
            details: semData,
          }),
          { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      return new Response(
        JSON.stringify({
          success: true,
          provider: "semaphore",
          senderName: rawSenderName || "Semaphore",
          recipient: semaphoreNumber,
          providerResponse: semData,
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 5. Fallback: TextBee Gateway API
    if (!textBeeApiKey || !textBeeDeviceId) {
      return new Response(
        JSON.stringify({
          success: false,
          error:
            "SMS gateway is not configured yet (set SEMAPHORE_API_KEY or TEXTBEE_API_KEY + TEXTBEE_DEVICE_ID secrets in Supabase).",
        }),
        { status: 503, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const textBeeUrl = `https://api.textbee.dev/api/v1/gateway/devices/${encodeURIComponent(textBeeDeviceId)}/send-sms`;
    const tbRes = await fetch(textBeeUrl, {
      method: "POST",
      headers: {
        "x-api-key": textBeeApiKey,
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
          provider: "textbee",
          error: `TextBee API error (${tbRes.status})`,
          details: tbData,
        }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({
        success: true,
        provider: "textbee",
        senderName: "SIM",
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
