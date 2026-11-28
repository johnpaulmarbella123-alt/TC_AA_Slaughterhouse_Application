/// <reference path="../edge-runtime.d.ts" />
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";

const PAYMONGO_API = "https://api.paymongo.com/v1";
const XENDIT_API = "https://api.xendit.co/v2";

function mapXenditChannel(channel: string, method: string): string {
  const s = `${channel} ${method}`.toLowerCase();
  if (s.includes("gcash")) return "GCash";
  if (s.includes("maya") || s.includes("paymaya")) return "Maya";
  if (s.includes("grab")) return "GrabPay";
  if (s.includes("shopee")) return "ShopeePay";
  if (s.includes("qrph") || s.includes("qr_ph") || s.includes("qr")) return "QR Ph";
  if (s.includes("card") || s.includes("visa") || s.includes("master")) return "Card";
  return "Online Payment";
}

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
    const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
    const supabaseServiceKey =
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || Deno.env.get("SUPABASE_ANON_KEY") || "";
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    let user: any = null;
    if (authHeader && authHeader.startsWith("Bearer ")) {
      const token = authHeader.replace("Bearer ", "");
      const { data: userData } = await supabase.auth.getUser(token);
      user = userData?.user;
    }

    // ─── 2. Determine Active Payment Gateway via Env Vars ───
    const gatewayEnv = (Deno.env.get("PAYMENT_GATEWAY") || "").trim().toLowerCase();
    const xenditSecretKey = (Deno.env.get("XENDIT_SECRET_KEY") || "").trim();
    const paymongoSecretKey = (Deno.env.get("PAYMONGO_SECRET_KEY") || "").trim();

    const useXendit =
      gatewayEnv === "xendit" ||
      (gatewayEnv !== "paymongo" && xenditSecretKey.length > 0);

    // ─── Helper: Check status for either Xendit or PayMongo ───
    async function checkStatus(linkId: string, reqIdParam: string | number | null) {
      if (!linkId && reqIdParam) {
        const { data: pRec } = await supabase
          .from("payments")
          .select("transaction_ref")
          .eq("request_id", Number(reqIdParam))
          .maybeSingle();
        if (pRec?.transaction_ref) {
          linkId = pRec.transaction_ref;
        }
      }

      if (!linkId) {
        return new Response(
          JSON.stringify({
            status: "not_found",
            message:
              "No online checkout session found for this request. Please verify the customer's payment reference directly in your merchant portal, then click Verify & Confirm below.",
          }),
          { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const isXenditRef =
        linkId.startsWith("xnd_") ||
        (useXendit && !linkId.startsWith("cs_") && !linkId.startsWith("link_"));

      // ─── XENDIT STATUS CHECK ───
      if (isXenditRef) {
        if (!xenditSecretKey) {
          return new Response(
            JSON.stringify({ error: "XENDIT_SECRET_KEY secret is not configured in Supabase" }),
            { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }

        const rawInvoiceId = linkId.startsWith("xnd_") ? linkId.slice(4) : linkId;
        const xenditRes = await fetch(`${XENDIT_API}/invoices/${encodeURIComponent(rawInvoiceId)}`, {
          method: "GET",
          headers: {
            Authorization: "Basic " + btoa(xenditSecretKey + ":"),
          },
        });

        const xenditData = await xenditRes.json();
        if (!xenditRes.ok) {
          return new Response(
            JSON.stringify({
              error: "Failed to check payment status",
              details: xenditData?.message || "Unknown Xendit error",
            }),
            { status: xenditRes.status, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }

        const rawStatus = String(xenditData?.status || "").toUpperCase();
        const resolvedStatus =
          rawStatus === "PAID" || rawStatus === "SETTLED"
            ? "paid"
            : rawStatus === "EXPIRED"
              ? "archived"
              : "unpaid";

        const detectedMethod = mapXenditChannel(
          String(xenditData?.payment_channel || ""),
          String(xenditData?.payment_method || "")
        );

        let autoVerified = false;
        if (resolvedStatus === "paid") {
          const extMatch = String(xenditData?.external_id || "").match(/tcaa-req-(\d+)/);
          const reqId =
            (extMatch && extMatch[1] ? Number(extMatch[1]) : null) ||
            (reqIdParam ? Number(reqIdParam) : null);

          if (reqId) {
            try {
              const { data: existingPay } = await supabase
                .from("payments")
                .select("id, status")
                .eq("request_id", reqId)
                .maybeSingle();

              if (existingPay && String(existingPay.status || "").toLowerCase() !== "paid") {
                await supabase
                  .from("payments")
                  .update({
                    status: "paid",
                    balance: 0,
                    payment_method: detectedMethod,
                    transaction_ref: linkId,
                  })
                  .eq("request_id", reqId);
                autoVerified = true;
              } else if (existingPay) {
                // Already paid — only ensure method/ref metadata is populated
                await supabase
                  .from("payments")
                  .update({
                    payment_method: detectedMethod,
                    transaction_ref: linkId,
                  })
                  .eq("request_id", reqId);
              }

              const { data: existingReq } = await supabase
                .from("requests")
                .select("status")
                .eq("id", reqId)
                .maybeSingle();
              const curReqStatus = String(existingReq?.status || "").toLowerCase();
              if (!["paid", "out_for_delivery", "released", "completed"].includes(curReqStatus)) {
                await supabase
                  .from("requests")
                  .update({ status: "paid" })
                  .eq("id", reqId);
                autoVerified = true;
              }
            } catch (dbErr) {
              console.error("Auto-verify Xendit payment error:", dbErr);
            }
          }
        }

        return new Response(
          JSON.stringify({
            link_id: linkId,
            status: resolvedStatus,
            auto_verified: autoVerified,
            detected_method: detectedMethod,
            payments: resolvedStatus === "paid" ? [xenditData] : [],
          }),
          { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // ─── PAYMONGO STATUS CHECK (Fallback) ───
      if (!paymongoSecretKey) {
        return new Response(
          JSON.stringify({ error: "PayMongo secret key not configured" }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const paymongoAuthHeader = "Basic " + btoa(paymongoSecretKey + ":");
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

      const hasPaidItem =
        Array.isArray(payments) &&
        payments.some((p: Record<string, unknown>) => {
          const directStatus = p?.status;
          const attrStatus = (p?.attributes as Record<string, unknown>)?.status;
          const dataAttrStatus = (
            (p?.data as Record<string, unknown>)?.attributes as Record<string, unknown>
          )?.status;
          return [directStatus, attrStatus, dataAttrStatus].some(
            (s) => String(s || "").toLowerCase() === "paid"
          );
        });

      const isSucceeded = String(paymentIntentStatus || "").toLowerCase() === "succeeded";

      const resolvedStatus =
        String(status || "").toLowerCase() === "paid" || hasPaidItem || isSucceeded
          ? "paid"
          : status;

      let detectedMethod = "Online Payment";
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

      if (resolvedStatus === "paid") {
        const reqIdFromMeta = metadata.request_id ? Number(metadata.request_id) : null;
        const reqMatch = remarks.match(/request_id:(\d+)/);
        const reqId =
          reqIdFromMeta ||
          (reqMatch && reqMatch[1] ? Number(reqMatch[1]) : null) ||
          (reqIdParam ? Number(reqIdParam) : null);

        if (reqId) {
          try {
            await supabase
              .from("payments")
              .update({
                payment_method: detectedMethod,
                transaction_ref: linkId,
              })
              .eq("request_id", reqId);
          } catch (dbErr) {
            console.error("Record transaction ref error:", dbErr);
          }
        }
      }

      return new Response(
        JSON.stringify({
          link_id: linkId,
          status: resolvedStatus,
          detected_method: detectedMethod,
          payments: payments,
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ─── POST: Create payment or check status ───
    if (req.method === "POST") {
      const body = await req.json();

      if (body.action === "check" || (body.link_id && !body.amount)) {
        return await checkStatus(body.link_id || "", body.request_id || null);
      }

      const { description, request_id } = body;
      let requestedAmount = Number(body.amount);

      if (!request_id) {
        return new Response(
          JSON.stringify({ error: "request_id is required" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // ─── 3. Server-Side Fee Verification & Authorization ───
      const { data: reqData, error: reqErr } = await supabase
        .from("requests")
        .select("id, user_id, status, customer_name")
        .eq("id", request_id)
        .maybeSingle();

      if (reqErr || !reqData) {
        return new Response(
          JSON.stringify({ error: "Slaughter request not found" }),
          { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      let isStaff = false;
      if (user) {
        const userEmail = (user.email || "").toLowerCase();
        const { data: profile } = await supabase
          .from("profiles")
          .select("role")
          .eq("id", user.id)
          .maybeSingle();
        if (
          profile?.role &&
          ["admin", "inspector", "cashier", "clerk"].includes(profile.role.toLowerCase())
        ) {
          isStaff = true;
        }

        const metaRole = (user.user_metadata?.role || "").toLowerCase();
        if (["admin", "inspector", "cashier", "clerk"].includes(metaRole)) {
          isStaff = true;
        }

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
              if (match) isStaff = true;
            }
          } catch (_) { }
        }

        if (
          !isStaff &&
          (userEmail.includes("tcaaslaughterhouse") ||
            userEmail.endsWith("@tabaco.gov.ph") ||
            userEmail.includes("admin") ||
            userEmail.includes("clerk") ||
            userEmail.includes("inspector"))
        ) {
          isStaff = true;
        }

        if (reqData.user_id && reqData.user_id !== user.id && !isStaff) {
          return new Response(
            JSON.stringify({ error: "Forbidden: You do not own this slaughter request" }),
            { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
      }

      const { data: paymentRecord } = await supabase
        .from("payments")
        .select("total_amount, status")
        .eq("request_id", request_id)
        .maybeSingle();

      if (paymentRecord && paymentRecord.total_amount) {
        requestedAmount = Number(paymentRecord.total_amount);
      }

      if (!requestedAmount || requestedAmount <= 0) {
        return new Response(
          JSON.stringify({ error: "Invalid payment amount" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // ─── XENDIT CREATE INVOICE (PHP) ───
      if (useXendit) {
        if (!xenditSecretKey) {
          return new Response(
            JSON.stringify({
              error: "Xendit is selected as PAYMENT_GATEWAY, but XENDIT_SECRET_KEY is not set in Supabase Secrets.",
            }),
            { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }

        const externalId = `tcaa-req-${request_id}-${Date.now()}`;
        const roundedAmount = Math.round(requestedAmount * 100) / 100;

        const xenditRes = await fetch(`${XENDIT_API}/invoices`, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: "Basic " + btoa(xenditSecretKey + ":"),
          },
          body: JSON.stringify({
            external_id: externalId,
            amount: roundedAmount,
            currency: "PHP",
            description:
              description ||
              `Tabaco City AA Slaughterhouse Service Fee - Request #${request_id}`,
            invoice_duration: 86400,
            items: [
              {
                name: "Slaughterhouse Service Fee",
                quantity: 1,
                price: roundedAmount,
              },
            ],
          }),
        });

        const xenditData = await xenditRes.json();
        if (!xenditRes.ok) {
          console.error("Xendit error:", JSON.stringify(xenditData));
          return new Response(
            JSON.stringify({
              error: "Failed to create checkout session",
              details: xenditData?.message || "Unknown Xendit error",
            }),
            { status: xenditRes.status, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }

        const linkId = `xnd_${xenditData.id}`;
        const checkoutUrl = xenditData.invoice_url;
        const referenceNumber = xenditData.external_id || externalId;

        try {
          await supabase
            .from("payments")
            .update({ transaction_ref: linkId })
            .eq("request_id", request_id);
        } catch (dbErr) {
          console.warn("Could not save Xendit transaction_ref to payments:", dbErr);
        }

        return new Response(
          JSON.stringify({
            link_id: linkId,
            checkout_url: checkoutUrl,
            reference_number: referenceNumber,
            status: "unpaid",
            amount_verified: roundedAmount,
          }),
          { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // ─── PAYMONGO CREATE CHECKOUT SESSION (Fallback) ───
      if (!paymongoSecretKey) {
        return new Response(
          JSON.stringify({ error: "PayMongo secret key not configured" }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const paymongoAuthHeader = "Basic " + btoa(paymongoSecretKey + ":");
      const amountInCentavos = Math.round(requestedAmount * 100);

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
                user_id: String(user?.id ?? reqData?.user_id ?? "walk_in"),
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

      try {
        await supabase
          .from("payments")
          .update({ transaction_ref: linkId })
          .eq("request_id", request_id);
      } catch (dbErr) {
        console.warn("Could not save transaction_ref to payments:", dbErr);
      }

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
      const linkId = url.searchParams.get("link_id") || "";
      const reqIdParam = url.searchParams.get("request_id") || null;
      return await checkStatus(linkId, reqIdParam);
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
