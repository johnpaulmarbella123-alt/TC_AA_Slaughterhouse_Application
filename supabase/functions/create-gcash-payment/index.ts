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
      const { data: profile } = await supabase
        .from("profiles")
        .select("role")
        .eq("id", user.id)
        .maybeSingle();
      const isStaff = ["admin", "inspector", "cashier", "clerk"].includes(
        (profile?.role || "").toLowerCase()
      );

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

      // Create a Payment Link via PayMongo API
      const paymongoRes = await fetch(`${PAYMONGO_API}/links`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: paymongoAuthHeader,
        },
        body: JSON.stringify({
          data: {
            attributes: {
              amount: amountInCentavos,
              description: description || `Slaughter Service Payment - Request #${request_id}`,
              remarks: `request_id:${request_id};user_id:${user.id}`,
            },
          },
        }),
      });

      const paymongoData = await paymongoRes.json();

      if (!paymongoRes.ok) {
        console.error("PayMongo error:", JSON.stringify(paymongoData));
        return new Response(
          JSON.stringify({
            error: "Failed to create payment link",
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

    // ─── GET: Check payment link status ───
    if (req.method === "GET") {
      const url = new URL(req.url);
      const linkId = url.searchParams.get("link_id");

      if (!linkId) {
        return new Response(
          JSON.stringify({ error: "link_id parameter required" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const paymongoRes = await fetch(`${PAYMONGO_API}/links/${linkId}`, {
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

      const status = paymongoData.data.attributes.status;
      const payments = paymongoData.data.attributes.payments;
      const remarks = (paymongoData.data.attributes.remarks || "") as string;

      const hasPaidItem = Array.isArray(payments) && payments.some((p: Record<string, unknown>) => {
        const directStatus = p?.status;
        const attrStatus = (p?.attributes as Record<string, unknown>)?.status;
        const dataAttrStatus = ((p?.data as Record<string, unknown>)?.attributes as Record<string, unknown>)?.status;
        return [directStatus, attrStatus, dataAttrStatus].some(
          (s) => String(s || "").toLowerCase() === "paid"
        );
      });

      const resolvedStatus = (String(status || "").toLowerCase() === "paid" || hasPaidItem)
          ? "paid"
          : status;

      // Auto-mark payment & request as paid on the server using Service Role key
      if (resolvedStatus === "paid") {
        const reqMatch = remarks.match(/request_id:(\d+)/);
        if (reqMatch && reqMatch[1]) {
          const reqId = Number(reqMatch[1]);
          try {
            await supabase
              .from("payments")
              .update({
                payment_method: "GCash",
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
