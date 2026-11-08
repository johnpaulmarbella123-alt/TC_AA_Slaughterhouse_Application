/// <reference path="../edge-runtime.d.ts" />
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";

const PAYMONGO_API = "https://api.paymongo.com/v1";

Deno.serve(async (req: Request) => {
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
  };

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // ─── 1. Authenticate Caller via Supabase JWT ───
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(
        JSON.stringify({ error: "Missing or invalid authorization header" }),
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
        JSON.stringify({ error: "Unauthorized: Invalid session" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const secretKey = Deno.env.get("PAYMONGO_SECRET_KEY");
    if (!secretKey) {
      return new Response(
        JSON.stringify({ error: "PayMongo secret key not configured" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const paymongoAuthHeader = "Basic " + btoa(secretKey + ":");

    // ─── POST: Create a payment link ───
    if (req.method === "POST") {
      const body = await req.json();
      const { description, request_id } = body;
      let requestedAmount = Number(body.amount);

      if (!request_id) {
        return new Response(
          JSON.stringify({ error: "request_id is required" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // ─── 2. Server-Side Fee Verification & Authorization ───
      // Verify request ownership and authoritatively fetch the calculated fee
      const { data: reqData, error: reqErr } = await supabase
        .from("requests")
        .select("id, user_id, status")
        .eq("id", request_id)
        .maybeSingle();

      if (reqErr || !reqData) {
        return new Response(
          JSON.stringify({ error: "Slaughter request not found" }),
          { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // Check user role for staff override
      let isStaff = false;
      const userEmail = (user.email || "").toLowerCase();

      // 1. Check profiles table
      const { data: profile } = await supabase
        .from("profiles")
        .select("role")
        .eq("id", user.id)
        .maybeSingle();
      if (profile?.role && ["admin", "inspector", "cashier", "clerk"].includes(profile.role.toLowerCase())) {
        isStaff = true;
      }

      // 2. Check user metadata
      const metaRole = (user.user_metadata?.role || "").toLowerCase();
      if (["admin", "inspector", "cashier", "clerk"].includes(metaRole)) {
        isStaff = true;
      }

      // 3. Check system_settings -> staff_accounts
      if (!isStaff && userEmail) {
        try {
          const { data: staffSetting } = await supabase
            .from("system_settings")
            .select("value")
            .eq("key", "staff_accounts")
            .maybeSingle();

          if (staffSetting?.value && Array.isArray(staffSetting.value)) {
            const match = staffSetting.value.find(
              (s: any) => (s?.email || "").toLowerCase() === userEmail && s?.isActive !== false
            );
            if (match) {
              isStaff = true;
            }
          }
        } catch (_) {}
      }

      // 4. Default admin accounts or domain check
      if (!isStaff && (userEmail.includes("tcaaslaughterhouse") || userEmail.endsWith("@tabaco.gov.ph") || userEmail.includes("admin"))) {
        isStaff = true;
      }

      if (reqData.user_id !== user.id && !isStaff) {
        return new Response(
          JSON.stringify({ error: "Forbidden: You do not own this slaughter request" }),
          { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // Check if a payment entry exists with authoritative total
      const { data: paymentRecord } = await supabase
        .from("payments")
        .select("total_amount, status")
        .eq("request_id", request_id)
        .maybeSingle();

      if (paymentRecord && paymentRecord.total_amount) {
        // Enforce authoritative database amount to prevent client tampering
        requestedAmount = Number(paymentRecord.total_amount);
      }

      if (!requestedAmount || requestedAmount <= 0) {
        return new Response(
          JSON.stringify({ error: "Invalid payment amount" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // PayMongo expects amount in centavos (integer)
      const amountInCentavos = Math.round(requestedAmount * 100);

      // Create a PayMongo Checkout Session enabling all payment methods (GCash, Maya, Cards, GrabPay, QR Ph)
      const paymongoRes = await fetch(`${PAYMONGO_API}/checkout_sessions`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: paymongoAuthHeader,
        },
        body: JSON.stringify({
          data: {
            attributes: {
              send_email_receipt: false,
              show_description: true,
              show_line_items: true,
              description: description || `Slaughter Service Online Payment - Request #${request_id}`,
              line_items: [
                {
                  currency: "PHP",
                  amount: amountInCentavos,
                  name: "Slaughterhouse Service Fee",
                  quantity: 1,
                },
              ],
              payment_method_types: ["gcash", "paymaya", "card", "grab_pay", "qrph"],
              metadata: {
                request_id: String(request_id),
                user_id: String(user.id),
              },
            },
          },
        }),
      });

      const paymongoData = await paymongoRes.json();

      if (!paymongoRes.ok) {
        console.error("PayMongo error:", JSON.stringify(paymongoData));
        return new Response(
          JSON.stringify({
            error: "Failed to create checkout session",
            details: paymongoData?.errors?.[0]?.detail || "Unknown error",
          }),
          { status: paymongoRes.status, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const linkId = paymongoData.data.id;
      const checkoutUrl = paymongoData.data.attributes.checkout_url;
      const referenceNumber = paymongoData.data.attributes.reference_number;
      const status = paymongoData.data.attributes.status;

      return new Response(
        JSON.stringify({
          link_id: linkId,
          checkout_url: checkoutUrl,
          reference_number: referenceNumber,
          status: status,
          amount_verified: requestedAmount,
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ─── GET: Check payment status ───
    if (req.method === "GET") {
      const url = new URL(req.url);
      const linkId = url.searchParams.get("link_id");

      if (!linkId) {
        return new Response(
          JSON.stringify({ error: "link_id parameter required" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const isCheckoutSession = linkId.startsWith("cs_");
      const endpoint = isCheckoutSession
        ? `${PAYMONGO_API}/checkout_sessions/${linkId}`
        : `${PAYMONGO_API}/links/${linkId}`;

      const paymongoRes = await fetch(endpoint, {
        method: "GET",
        headers: {
          Authorization: paymongoAuthHeader,
        },
      });

      const paymongoData = await paymongoRes.json();

      if (!paymongoRes.ok) {
        return new Response(
          JSON.stringify({
            error: "Failed to check payment status",
            details: paymongoData?.errors?.[0]?.detail || "Unknown error",
          }),
          { status: paymongoRes.status, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const attr = paymongoData.data?.attributes || {};
      const status = attr.status;
      const payments = attr.payments || [];
      const paymentIntentStatus = attr.payment_intent?.attributes?.status;
      const remarks = (attr.remarks || "") as string;
      const metadata = attr.metadata || {};

      const hasPaidItem = Array.isArray(payments) && payments.some((p: Record<string, unknown>) => {
        const directStatus = p?.status;
        const attrStatus = (p?.attributes as Record<string, unknown>)?.status;
        const dataAttrStatus = ((p?.data as Record<string, unknown>)?.attributes as Record<string, unknown>)?.status;
        return [directStatus, attrStatus, dataAttrStatus].some(
          (s) => String(s || "").toLowerCase() === "paid"
        );
      });

      const isSucceeded = String(paymentIntentStatus || "").toLowerCase() === "succeeded";

      const resolvedStatus = (String(status || "").toLowerCase() === "paid" || hasPaidItem || isSucceeded)
        ? "paid"
        : status;

      let detectedMethod = "Online (PayMongo)";
      if (Array.isArray(payments) && payments.length > 0) {
        for (const p of payments) {
          const srcType =
            p?.attributes?.source?.type ||
            p?.data?.attributes?.source?.type ||
            p?.source?.type ||
            p?.attributes?.payment_method_type ||
            "";
          const s = String(srcType).toLowerCase();
          if (s.includes("gcash")) {
            detectedMethod = "GCash";
            break;
          } else if (s.includes("maya") || s.includes("paymaya")) {
            detectedMethod = "Maya";
            break;
          } else if (s.includes("card") || s.includes("visa") || s.includes("mastercard")) {
            detectedMethod = "Card";
            break;
          } else if (s.includes("grab")) {
            detectedMethod = "GrabPay";
            break;
          }
        }
      }

      // Auto-mark payment & request as paid on the server using Service Role key
      if (resolvedStatus === "paid") {
        const reqIdFromMeta = metadata.request_id ? Number(metadata.request_id) : null;
        const reqMatch = remarks.match(/request_id:(\d+)/);
        const reqId = reqIdFromMeta || (reqMatch && reqMatch[1] ? Number(reqMatch[1]) : null);

        if (reqId) {
          try {
            await supabase
              .from("payments")
              .update({
                payment_method: detectedMethod,
                status: "paid",
                balance: 0,
              })
              .eq("request_id", reqId);
            await supabase
              .from("requests")
              .update({ status: "paid" })
              .eq("id", reqId);
          } catch (dbErr) {
            console.error("Auto-confirm payment error:", dbErr);
          }
        }
      }

      return new Response(
        JSON.stringify({
          link_id: linkId,
          status: resolvedStatus,  // "unpaid", "paid", "archived"
          detected_method: detectedMethod,
          payments: payments,
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({ error: "Method not allowed" }),
      { status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err: unknown) {
    console.error("Edge function error:", err);
    const message = err instanceof Error ? err.message : String(err);
    return new Response(
      JSON.stringify({ error: message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
