---
title: "Admin - Payment & Cashiering"
category: "Module Reference"
created: 2026-09-26
last_updated: 2026-09-26
tags:
  - module
  - admin
  - cashiering
  - payments
  - tariff
---

# Admin Module: Payment & Cashiering

**Source File**: `admin_panel/lib/screens/payment_cashiering_page.dart`  
**Target Roles**: City Slaughterhouse Cashiers, Revenue Collectors.

---

## Purpose & Functionality
Manages financial settlements for slaughtering, inspection, and facility usage in strict compliance with municipal revenue ordinances.

---

## Official Slaughterhouse Tariff Calculation

```dart
Total Fee = Vet Health Cert (₱50.00)
          + Permit to Slaughter (₱60.00)
          + Facility Fee (₱60.00)
          + Corral Fee (₱40.00)
          + Ante-Mortem Inspection (₱40.00)
          + Post-Mortem Inspection (₱5.00 × Carcass Weight in kg)
          + Delivery Van Transport (₱60.00, Market requests only)
```

---

## Key Operations & Workflows
- **Cash Settlement**: Cashier accepts cash at window, verifies balance, clicks "Record Payment", transitions `payments.status = 'paid'`, generates receipt number `RCP-YYYY-XXX`, and sets `requests.status = 'paid'`.
- **GCash Online Verification**: Displays PayMongo transaction reference and link status for digital settlements.

---

## Related Knowledge Links
- [[Table - payments]]
- [[Admin - Meat Releasing]]
- [[PayMongo Payment Gateway Integration]]
