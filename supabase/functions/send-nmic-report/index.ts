/// <reference types="https://esm.sh/@supabase/functions-js/src/edge-runtime.d.ts" />

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
    const body = await req.json();
    const { apiKey, sender, to, subject, text, attachments } = body;

    const resendKey = apiKey || Deno.env.get("RESEND_API_KEY");
    if (!resendKey) {
      return new Response(
        JSON.stringify({ success: false, error: "Resend API key is not provided or configured." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${resendKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: sender || "TCAA Slaughterhouse <onboarding@resend.dev>",
        to: Array.isArray(to) ? to : [to],
        subject: subject,
        text: text,
        attachments: attachments || [],
      }),
    });

    const data = await res.json();
    if (res.ok) {
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
  } catch (err) {
    return new Response(
      JSON.stringify({ success: false, error: `Server exception: ${err?.message || err}` }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

