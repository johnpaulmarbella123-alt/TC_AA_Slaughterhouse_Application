/// <reference path="../edge-runtime.d.ts" />
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";

function last10Digits(raw: string): string {
  const digits = raw.replace(/\D/g, "");
  if (digits.length >= 10) {
    return digits.slice(-10);
  }
  return digits;
}

function parseReplyAction(msg: string): "confine" | "take_back" | "reply" {
  const upper = msg.toUpperCase();
  if (/\b(TAKE\s*BACK|TAKEBACK|PICK\s*UP|PICKUP|RETRIEVE|PULL\s*OUT|KUHAON|KUNIN)\b/.test(upper)) {
    return "take_back";
  }
  if (/\b(CONFINE|OBSERVE|OBSERVATION|KEEP|YES|AGREE|OK|OKAY|SIGE)\b/.test(upper)) {
    return "confine";
  }
  return "reply";
}

Deno.serve(async (req: Request) => {
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-webhook-secret",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ success: false, error: "Method not allowed" }),
      { status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  try {
    // Optional shared secret verification if TEXTBEE_WEBHOOK_SECRET is configured
    const expectedSecret = (Deno.env.get("TEXTBEE_WEBHOOK_SECRET") || "").trim();
    if (expectedSecret.length > 0) {
      const url = new URL(req.url);
      const provided =
        req.headers.get("x-webhook-secret") ||
        url.searchParams.get("secret") ||
        "";
      if (provided !== expectedSecret) {
        return new Response(
          JSON.stringify({ success: false, error: "Unauthorized webhook secret" }),
          { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    const body = await req.json();
    const payload = (body?.data && typeof body.data === "object") ? body.data : body;

    const rawSender = (
      payload?.sender ??
      payload?.from ??
      payload?.phone ??
      payload?.phoneNumber ??
      body?.sender ??
      ""
    ).toString().trim();

    const rawMessage = (
      payload?.message ??
      payload?.text ??
      payload?.body ??
      payload?.content ??
      body?.message ??
      ""
    ).toString().trim();

    const receivedAt = (
      payload?.receivedAt ??
      payload?.received_at ??
      payload?.timestamp ??
      new Date().toISOString()
    ).toString();

    if (!rawSender || !rawMessage) {
      return new Response(
        JSON.stringify({ success: false, error: "Missing sender or message in webhook payload" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const senderTail = last10Digits(rawSender);
    const parsedAction = parseReplyAction(rawMessage);

    const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
    const serviceKey =
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || Deno.env.get("SUPABASE_ANON_KEY") || "";
    const supabase = createClient(supabaseUrl, serviceKey);

    // Find the most recent matching walk-in request by contact_number (last 10 digits)
    const { data: candidates, error: reqErr } = await supabase
      .from("requests")
      .select("id, customer_name, contact_number, status, livestock_type, animal_count")
      .not("contact_number", "is", null)
      .order("created_at", { ascending: false })
      .limit(150);

    if (reqErr) {
      console.error("Error querying requests:", reqErr);
    }

    const matching = (candidates || []).filter((r: Record<string, unknown>) => {
      const cPhone = (r.contact_number ?? "").toString();
      return senderTail.length >= 10 && last10Digits(cPhone) === senderTail;
    });

    // Prioritize failed/active inspection requests first
    const priorityStatuses = new Set([
      "anti_mortem_failed",
      "post_mortem_failed",
      "condemned",
      "delay_error",
      "pickup_scheduled",
      "slaughter_started",
      "doc_verified",
    ]);

    const matchedReq =
      matching.find((r: Record<string, unknown>) =>
        priorityStatuses.has((r.status ?? "").toString().toLowerCase())
      ) || matching[0] || null;

    const reqId = matchedReq ? matchedReq.id : null;

    // 1. Insert into public.walkin_sms_replies
    const { error: insertErr } = await supabase.from("walkin_sms_replies").insert({
      request_id: reqId,
      sender_phone: rawSender,
      message: rawMessage,
      parsed_action: parsedAction,
      source: "textbee_webhook",
      received_at: receivedAt,
    });

    if (insertErr) {
      console.error("Error inserting walkin_sms_replies:", insertErr);
      return new Response(
        JSON.stringify({ success: false, error: insertErr.message }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 2. If matched to an active request, update anti_mortem_response when decision keyword detected
    if (matchedReq && reqId != null) {
      const reqStatus = (matchedReq.status ?? "").toString().toLowerCase();
      if (
        (parsedAction === "confine" || parsedAction === "take_back") &&
        (reqStatus === "anti_mortem_failed" || reqStatus === "delay_error")
      ) {
        await supabase
          .from("requests")
          .update({
            anti_mortem_response: parsedAction,
            anti_mortem_response_at: new Date().toISOString(),
          })
          .eq("id", reqId);
      }

      // 3. Notify Inspector via staff_notifications bell
      const refNo = `MI-${new Date().getFullYear()}-${String(reqId).padStart(3, "0")}`;
      const custName = (matchedReq.customer_name ?? "Walk-In Customer").toString();
      const actionLabel =
        parsedAction === "confine"
          ? "CONFINE"
          : parsedAction === "take_back"
            ? "TAKE BACK"
            : "SMS Reply";

      await supabase.from("staff_notifications").insert({
        target_role: "Inspector",
        type: "walkin_sms_reply",
        title: `Walk-In SMS Reply (${actionLabel})`,
        message: `${custName} (${refNo}) replied via SMS: "${rawMessage}"`,
        request_id: reqId,
        reference_no: refNo,
        read_by: [],
      });
    }

    return new Response(
      JSON.stringify({
        success: true,
        matchedRequestId: reqId,
        parsedAction,
        sender: rawSender,
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
