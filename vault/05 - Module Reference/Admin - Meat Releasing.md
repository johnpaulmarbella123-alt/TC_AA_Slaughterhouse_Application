---
title: "Admin - Meat Releasing"
category: "Module Reference"
created: 2026-09-26
last_updated: 2026-09-26
tags:
  - module
  - admin
  - dispatch
  - meat-release
---

# Admin Module: Meat Releasing

**Source File**: `admin_panel/lib/screens/meat_releasing_page.dart`  
**Target Roles**: Dispatch Officers, Security Gate Guards, Cold Storage Handlers.

---

## Purpose & Functionality
The final physical operational checkpoint before dressed meat carcasses leave the slaughterhouse facility. Ensures no meat is dispatched without:
1. Valid Official Receipt (`payments.status == 'paid'`).
2. Approved Meat Inspection Certificate (MIC).
3. Verified recipient identity or accredited delivery van driver.

---

## Key Operations & Workflows
- **Gate Pass Verification**: Validates digital receipt `RCP-YYYY-XXX`.
- **Dispatch Confirmation**: Updates `requests.status = 'completed'` and stamps `requests.released_at = NOW()`.
- **Customer Alert**: Triggers a notification informing the client that the batch has been successfully dispatched.

---

## Related Knowledge Links
- [[Table - requests]]
- [[Admin - Reports & Records]]
- [[Mobile - Receipt & QR Verification]]
