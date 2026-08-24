/// <reference types="https://esm.sh/@supabase/functions-js/src/edge-runtime.d.ts" />

const PAYMONGO_API = "https://api.paymongo.com/v1";

Deno.serve(async (req: Request) => {
  // CORS headers for Flutter app
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
    const secretKey = Deno.env.get("PAYMONGO_SECRET_KEY");
    if (!secretKey) {
      return new Response(
        JSON.stringify({ error: "PayMongo secret key not configured" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const authHeader = "Basic " + btoa(secretKey + ":");

    // ─── POST: Create a payment link ───
    if (req.method === "POST") {
      const body = await req.json();
      const { amount, description, request_id } = body;

      if (!amount || amount <= 0) {
        return new Response(
          JSON.stringify({ error: "Invalid amount" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // PayMongo expects amount in centavos (integer)
      const amountInCentavos = Math.round(amount * 100);

      // Create a Payment Link via PayMongo API
      const paymongoRes = await fetch(`${PAYMONGO_API}/links`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: authHeader,
        },
        body: JSON.stringify({
          data: {
            attributes: {
              amount: amountInCentavos,
              description: description || `Slaughter Service Payment - Request #${request_id}`,
              remarks: `request_id:${request_id}`,
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
          Authorization: authHeader,
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

      return new Response(
        JSON.stringify({
          link_id: linkId,
          status: status,  // "unpaid", "paid", "archived"
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
