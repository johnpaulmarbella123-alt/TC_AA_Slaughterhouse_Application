/// <reference path="../edge-runtime.d.ts" />
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";
import nodemailer from "npm:nodemailer@6.9.16";

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

    // ─── 2. RBAC: Verify Caller is Staff (Super Admin, Admin, or Inspector) ───
    const { data: profile } = await supabase
      .from("profiles")
      .select("role, display_name")
      .eq("id", user.id)
      .maybeSingle();

    const profileRole = (profile?.role || "").toLowerCase();
    const metaRole = String(user.user_metadata?.role || "").toLowerCase();
    const userEmail = String(user.email || "").toLowerCase();
    const allowedRoles = ["super_admin", "super admin", "superadmin", "admin", "inspector"];
    const isAuthorized =
      allowedRoles.includes(profileRole) ||
      allowedRoles.includes(metaRole) ||
      userEmail === "tcaaslaughterhouse@gmail.com" ||
      userEmail === "admin@tabaco.gov.ph";

    if (!isAuthorized) {
      return new Response(
        JSON.stringify({ success: false, error: "Forbidden: Only Administrators and Meat Inspectors can transmit NMIS reports." }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const body = await req.json();
    const { apiKey, sender, to, subject, text, attachments, reportType, periodLabel } = body;

    const recipientList = (Array.isArray(to) ? to : [to])
      .map((e: unknown) => String(e ?? "").trim())
      .filter((e: string) => e.length > 0);

    if (recipientList.length === 0) {
      return new Response(
        JSON.stringify({ success: false, error: "Recipient email address is required." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const gmailUser = (Deno.env.get("GMAIL_USER") || "").trim();
    const gmailAppPassword = (Deno.env.get("GMAIL_APP_PASSWORD") || "").replace(/\s+/g, "").trim();
    const resendKey = (apiKey || Deno.env.get("RESEND_API_KEY") || "").trim();

    let messageId = "";
    let provider = "";

    // ─── 3A. Primary: Direct Gmail SMTP (works with any recipient email, no custom domain needed) ───
    if (gmailUser && gmailAppPassword) {
      const transporter = nodemailer.createTransport({
        host: "smtp.gmail.com",
        port: 465,
        secure: true,
        auth: {
          user: gmailUser,
          pass: gmailAppPassword,
        },
      });

      const formattedAttachments = Array.isArray(attachments)
        ? attachments.map((att: { filename?: string; content?: string }) => ({
            filename: att.filename || "NMIS_Report.pdf",
            content: att.content || "",
            encoding: "base64",
            contentType: "application/pdf",
          }))
        : [];

      const info = await transporter.sendMail({
        from: `"Tabaco City Slaughterhouse" <${gmailUser}>`,
        to: recipientList.join(", "),
        subject: subject || "Official NMIS Report Transmittal",
        text: text || "",
        attachments: formattedAttachments,
      });

      messageId = String(info?.messageId || "gmail-smtp-sent");
      provider = "gmail_smtp";
    } else if (resendKey) {
      // ─── 3B. Fallback: Resend API ───
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
      if (!res.ok) {
        const errMsg = data.message || data.name || JSON.stringify(data);
        return new Response(
          JSON.stringify({ success: false, error: `Resend error (${res.status}): ${errMsg}` }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
      messageId = String(data.id || "resend-sent");
      provider = "resend";
    } else {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Direct email sender is not configured yet. Please add GMAIL_USER and GMAIL_APP_PASSWORD (or RESEND_API_KEY) in Supabase Edge Function Secrets.",
        }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ─── 4. Log into nmic_transmissions Audit Trail ───
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
      JSON.stringify({ success: true, id: messageId, provider }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    return new Response(
      JSON.stringify({ success: false, error: `Server exception: ${message}` }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
