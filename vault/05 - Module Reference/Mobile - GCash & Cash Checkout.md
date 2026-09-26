---
title: "Mobile - GCash & Cash Checkout"
category: "Module Reference"
created: 2026-09-26
last_updated: 2026-09-26
tags:
  - module
  - mobile
  - checkout
  - gcash
  - paymongo
---

# Mobile Module: GCash & Cash Checkout

**Source File**: `mobile_app/lib/screen/select_payment_screen.dart`  
**Target Roles**: Meat Dealers, Clients settling slaughterhouse service fees.

---

## Purpose & Functionality
Allows customers whose meat has completed post-mortem inspection and carcass weighing to settle their assessed municipal fees digitally or opt for cash settlement upon arrival at the abattoir counter.

---

## Payment Channels
1. **GCash via PayMongo Link**:
   - Invokes `create-gcash-payment` Edge Function.
   - Redirects customer to secure PayMongo GCash web checkout.
   - Polls and verifies link payment status upon application resumption.
2. **Cash on Pickup**:
   - Queues invoice for physical cashiering settlement at the slaughterhouse release window.

---

## Related Knowledge Links
- [[PayMongo Payment Gateway Integration]]
- [[Admin - Payment & Cashiering]]
- [[Table - payments]]
- [[Security & Vulnerability Assessment]]
