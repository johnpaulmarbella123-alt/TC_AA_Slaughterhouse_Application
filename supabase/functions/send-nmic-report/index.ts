/// <reference path="../edge-runtime.d.ts" />
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";

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
    // ─── 1. Authenticate Caller via Supabase JWT ───
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(
        JSON.stringify({ success: false, error: "Missing or invalid authorization token" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
    const token = authHeader.replace("Bearer ", "");

    const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || Deno.env.get("SUPABASE_ANON_KEY") || "";
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const { data: { user }, error: authError } = await supabase.auth.getUser(token);
    if (authError || !user) {
      return new Response(
        JSON.stringify({ success: false, error: "Unauthorized: Invalid or expired session" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ─── 2. RBAC: Verify Caller is Staff (Admin or Inspector) ───
    const { data: profile } = await supabase
      .from("profiles")
      .select("role, display_name")
      .eq("id", user.id)
      .maybeSingle();

    const userRole = (profile?.role || "").toLowerCase();
    const isAuthorized = ["admin", "inspector"].includes(userRole);

    if (!isAuthorized) {
      return new Response(
        JSON.stringify({ success: false, error: "Forbidden: Only Administrators and Meat Inspectors can transmit NMIC reports." }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const body = await req.json();
    const { apiKey, sender, to, subject, text, attachments, reportType, periodLabel } = body;

    const resendKey = apiKey || Deno.env.get("RESEND_API_KEY");
    if (!resendKey) {
      return new Response(
        JSON.stringify({ success: false, error: "Resend API key is not configured on the abattoir server." }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const recipientList = Array.isArray(to) ? to : [to];

    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${resendKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: sender || "TCAA Slaughterhouse <onboarding@resend.dev>",
        to: recipientList,
        subject: subject,
        text: text,
        attachments: attachments || [],
      }),
    });

    const data = await res.json();
    if (res.ok) {
      // ─── 3. Log into nmic_transmissions Audit Trail ───
      try {
        await supabase.from("nmic_transmissions").insert({
          report_type: reportType || "official_transmission",
          period_label: periodLabel || new Date().toISOString().split("T")[0],
          recipient_email: recipientList.join(", "),
          transmittal_subject: subject,
          transmittal_body: text,
          sent_by: profile?.display_name || user.email || "Authorized Staff",
          status: "sent",
        });
      } catch (logErr) {
        console.warn("Failed to log transmission audit record:", logErr);
      }

      return new Response(
        JSON.stringify({ success: true, id: data.id, data }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    } else {
      const errMsg = data.message || data.name || JSON.stringify(data);
      return new Response(
        JSON.stringify({ success: false, error: `Resend error (${res.status}): ${errMsg}` }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    return new Response(
      JSON.stringify({ success: false, error: `Server exception: ${message}` }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
