---
title: "PayMongo Payment Gateway Integration"
category: "Architecture"
created: 2026-09-26
last_updated: 2026-09-26
tags:
  - payments
  - paymongo
  - gcash
  - edge-functions
---

# PayMongo Payment Gateway Integration

The **PayMongo Integration** enables meat dealers and slaughterhouse clients to settle slaughtering, ante/post-mortem inspection, corral, and facility fees directly via GCash, Maya, and credit/debit channels.

---

## Complete Transaction Lifecycle

```mermaid
sequenceDiagram
    autonumber
    actor Customer as Mobile App User
    participant Flutter as Mobile App (SelectPaymentScreen)
    participant Edge as Edge Function (create-gcash-payment)
    participant PayMongo as PayMongo API v1
    participant DB as Supabase PostgreSQL

    Customer->>Flutter: Selects GCash & taps "Pay ₱X.XX"
    Flutter->>Edge: HTTP POST /create-gcash-payment<br/>{ amount, description, request_id }
    Note over Edge: Validates amount > 0<br/>Converts to Centavos (amount * 100)
    Edge->>PayMongo: POST /links with Basic Auth (Secret Key)
    PayMongo-->>Edge: Returns link_id, checkout_url, reference_number
    Edge-->>Flutter: JSON response with checkout_url
    Flutter->>Customer: Opens checkout_url in external browser
    Customer->>PayMongo: Completes GCash authentication & payment
    Customer->>Flutter: Switches back to Mobile App
    Flutter->>Flutter: Lifecycle state 'resumed' triggers status check
    Flutter->>Edge: HTTP GET /create-gcash-payment?link_id=xxx
    Edge->>PayMongo: GET /links/:id
    PayMongo-->>Edge: status: "paid", payments: [...]
    Edge-->>Flutter: status: "paid"
    Flutter->>DB: UPDATE payments SET status = 'paid'
    Flutter->>DB: UPDATE requests SET status = 'paid'
    Flutter->>Customer: Shows Payment Confirmed & Receipt View
```

---

## Edge Function Implementation Highlights

1. **Amount Normalization**:
   ```typescript
   // PayMongo API requires currency amounts in centavos integer format
   const amountInCentavos = Math.round(amount * 100);
   ```
2. **Metadata Tracking**:
   ```typescript
   body: JSON.stringify({
     data: {
       attributes: {
         amount: amountInCentavos,
         description: description || `Slaughter Service Payment - Request #${request_id}`,
         remarks: `request_id:${request_id}`,
       },
     },
   })
   ```
3. **CORS Security**:
   - Headers explicitly define `Access-Control-Allow-Origin: *` to permit Flutter Web and Mobile preflight options requests.

---

## Security Vulnerabilities & Best Practices

1. **Absence of Server-to-Server Webhook**:
   - Currently, payment verification relies on **Client-Side Polling** (`didChangeAppLifecycleState` and periodic timer).
   - If a customer completes the GCash payment but closes the browser or loses internet connection before returning to the app, the database will remain in an `unpaid` or `payment_pending` state!
   - **Recommendation**: Implement a dedicated PayMongo Webhook listener (`POST /paymongo-webhook`) in Supabase Edge Functions that updates `payments` and `requests` atomically upon receiving `payment.paid` event. See [[Security & Vulnerability Assessment]].

---

## Related Knowledge Links
- [[Flutter Mobile App Architecture]]
- [[Supabase Backend & Edge Runtime]]
- [[Security & Vulnerability Assessment]]
