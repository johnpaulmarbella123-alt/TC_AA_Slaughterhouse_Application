---
title: "Flutter Mobile App Architecture"
category: "Architecture"
created: 2026-09-26
last_updated: 2026-09-26
tags:
  - mobile
  - flutter
  - client
  - android
  - ios
---

# Flutter Mobile App Architecture

The **Mobile Client Application** (`tc_aa_slaughterhouse`) provides meat dealers, farmers, market stall operators, and the general public with a native mobile gateway (Android/iOS) to interface with Tabaco City Slaughterhouse operations.

---

## Source Code Structure (`mobile_app/lib`)

```
mobile_app/lib/
├── main.dart                               # Entry point, Supabase init, .env loading
├── auth/
│   ├── auth_gate.dart                      # Auth state stream listener (Welcome vs Home)
│   └── auth_server.dart                    # Profile loading & session management
├── pages/
│   ├── home_page.dart                      # Main dashboard, quick actions, status stream
│   ├── login_page.dart                     # Email/Password authentication
│   └── signup_page.dart                    # Registration & initial profile creation
├── screen/
│   ├── requests.dart                       # New slaughter request booking form
│   ├── review.dart                         # Customer review & ratings submission
│   ├── payment.dart                        # Payment history & active invoice list
│   ├── select_payment_screen.dart          # GCash (PayMongo) / Cash checkout screen
│   ├── receipt_detail_screen.dart          # Digital official receipt with barcode/details
│   ├── condemnation_slip_screen.dart       # Veterinary condemnation notification & slip
│   ├── report_illegal_slaughter_screen.dart# Whistleblower reporting with photo evidence
│   ├── notify.dart                         # Realtime notifications center
│   ├── profile.dart                        # User profile management & avatar upload
│   ├── gallery.dart                        # Slaughterhouse facility gallery & info
│   ├── welcome.dart                        # Splash & intro onboarding screen
│   └── dashed_line.dart                    # Custom UI receipt divider widget
└── otp_screen.dart                         # OTP verification dialog
```

---

## Authentication & Session Lifecycle

1. **Authentication Gate (`AuthGate`)**:
   - Uses `Supabase.instance.client.auth.onAuthStateChange` to listen to token refreshes and login/logout events.
   - If an active session exists, mounts `HomeScreen()`. Otherwise, mounts `WelcomeScreen()`.
2. **Profile Synchronization**:
   - `AuthServer` loads the corresponding row from the `profiles` table matching `auth.uid()`.
   - Manages user metadata such as full name, phone number, and avatar URL.

---

## Payment & Polling Architecture

```mermaid
sequenceDiagram
    autonumber
    actor User as Mobile User
    participant App as Flutter Mobile App
    participant Edge as Supabase Edge Function
    participant PayMongo as PayMongo API
    participant DB as PostgreSQL DB

    User->>App: Tap "Pay with GCash"
    App->>Edge: POST /create-gcash-payment {amount, request_id}
    Edge->>PayMongo: POST /v1/links (Centavos, secret key)
    PayMongo-->>Edge: Returns checkout_url & link_id
    Edge-->>App: {checkout_url, link_id}
    App->>App: Open checkout_url in Browser (url_launcher)
    App->>App: Start Polling Timer (every 5s)
    User->>PayMongo: Completes GCash Payment
    User->>App: Returns to App (didChangeAppLifecycleState)
    App->>Edge: GET /create-gcash-payment?link_id=xxx
    Edge->>PayMongo: GET /v1/links/:id
    PayMongo-->>Edge: status: "paid"
    Edge-->>App: status: "paid"
    App->>DB: UPDATE payments SET status = 'paid'
    App->>DB: UPDATE requests SET status = 'paid'
    App->>User: Display Success Dialog & Receipt
```

---

## Code Smells & Architectural Insights

1. **Direct Database Updates from Client**:
   - As noted in the audit, the mobile app writes directly to the `payments` and `requests` tables when confirming transactions instead of relying on a secure webhook or database trigger.
2. **Missing State Management Library**:
   - State across screens is managed via local `StatefulWidget` `setState()` calls. While lightweight, shared application state (such as live badge counts) requires repeated manual queries.
3. **Hardcoded URLs**:
   - In `select_payment_screen.dart`, URL manipulation `supabase.rest.url.replaceAll('/rest/v1', '')` is used to construct edge function URLs. Recommended to use `supabase.functions.invoke()` directly for cleaner integration.

---

## Related Knowledge Links
- [[PayMongo Payment Gateway Integration]]
- [[Mobile - Client Request Booking]]
- [[Mobile - GCash & Cash Checkout]]
- [[Comprehensive System Audit Report]]
