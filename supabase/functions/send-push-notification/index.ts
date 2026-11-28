// Supabase Edge Function: send-push-notification
// Delivers real-time FCM HTTP v1 push notifications (with Android app icon badge count)
// to customer devices even when the mobile app is closed / terminated.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

function base64UrlEncode(input: Uint8Array | string): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let binary = "";
  for (let i = 0; i < bytes.byteLength; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const clean = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  const binary = atob(clean);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}

async function getFirebaseAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = base64UrlEncode(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claimSet = base64UrlEncode(
    JSON.stringify({
      iss: sa.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    }),
  );

  const signingInput = `${header}.${claimSet}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(signingInput),
  );
  const jwt = `${signingInput}.${base64UrlEncode(new Uint8Array(signature))}`;

  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  if (!tokenRes.ok) {
    const errText = await tokenRes.text();
    throw new Error(`Google OAuth token error: ${tokenRes.status} ${errText}`);
  }
  const tokenJson = await tokenRes.json();
  return tokenJson.access_token as string;
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = await req.json();
    // Supports direct invoke ({ user_id, title, message, ... }) or DB webhook ({ record: { ... } })
    const payload = body?.record && typeof body.record === "object" ? body.record : body;
    const userId = String(payload?.user_id ?? "").trim();
    const title = String(payload?.title ?? "Tabaco City Slaughterhouse").trim();
    const message = String(payload?.message ?? "You have a new update.").trim();
    const type = String(payload?.type ?? "general").trim();
    const referenceNo = String(payload?.reference_no ?? "").trim();

    if (!userId) {
      return new Response(
        JSON.stringify({ ok: false, skipped: true, reason: "Missing user_id" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 },
      );
    }

    const saRaw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
    if (!saRaw || !saRaw.trim()) {
      return new Response(
        JSON.stringify({
          ok: false,
          skipped: true,
          reason: "FIREBASE_SERVICE_ACCOUNT_JSON secret not configured yet",
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 },
      );
    }

    const sa: ServiceAccount = JSON.parse(saRaw);
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const supabase = createClient(supabaseUrl, serviceRoleKey);

    // 1. Fetch all registered FCM tokens for this customer
    const { data: tokenRows, error: tokenErr } = await supabase
      .from("user_push_tokens")
      .select("fcm_token")
      .eq("user_id", userId);

    if (tokenErr) {
      throw new Error(`Token lookup error: ${tokenErr.message}`);
    }

    const tokens = (tokenRows ?? [])
      .map((r: { fcm_token?: string }) => String(r.fcm_token ?? "").trim())
      .filter((t: string) => t.length > 0);

    if (tokens.length === 0) {
      return new Response(
        JSON.stringify({ ok: true, sent: 0, reason: "No registered device tokens for user" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 },
      );
    }

    // 2. Count unread notifications for launcher app icon badge
    let unreadCount = 1;
    try {
      const { count } = await supabase
        .from("notifications")
        .select("id", { count: "exact", head: true })
        .eq("user_id", userId)
        .eq("is_read", false);
      if (typeof count === "number" && count > 0) {
        unreadCount = count;
      }
    } catch (_) {}

    // 3. Send via FCM HTTP v1 API
    const accessToken = await getFirebaseAccessToken(sa);
    const fcmEndpoint = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;

    let sent = 0;
    const staleTokens: string[] = [];

    for (const token of tokens) {
      const fcmRes = await fetch(fcmEndpoint, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token,
            notification: {
              title,
              body: message,
            },
            android: {
              priority: "HIGH",
              notification: {
                channel_id: "tcaa_slaughter_alerts",
                sound: "default",
                notification_count: unreadCount,
              },
            },
            apns: {
              payload: {
                aps: {
                  badge: unreadCount,
                  sound: "default",
                },
              },
            },
            data: {
              route: "notify",
              type,
              reference_no: referenceNo,
              unread_count: String(unreadCount),
            },
          },
        }),
      });

      if (fcmRes.ok) {
        sent++;
      } else {
        const errBody = await fcmRes.text();
        if (errBody.includes("UNREGISTERED") || errBody.includes("INVALID_ARGUMENT")) {
          staleTokens.push(token);
        }
        console.error("FCM send error:", fcmRes.status, errBody);
      }
    }

    // 4. Prune expired / uninstalled device tokens
    if (staleTokens.length > 0) {
      await supabase.from("user_push_tokens").delete().in("fcm_token", staleTokens);
    }

    return new Response(
      JSON.stringify({ ok: true, sent, totalTokens: tokens.length, badge: unreadCount }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 },
    );
  } catch (err) {
    console.error("send-push-notification error:", err);
    return new Response(
      JSON.stringify({ ok: false, error: String(err) }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 500 },
    );
  }
});
