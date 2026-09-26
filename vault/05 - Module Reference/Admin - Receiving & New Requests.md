---
title: "Admin - Receiving & New Requests"
category: "Module Reference"
created: 2026-09-26
last_updated: 2026-09-26
tags:
  - module
  - admin
  - receiving
  - intake
---

# Admin Module: Receiving & New Requests

**Source File**: `admin_panel/lib/screens/receiving_requests_page.dart`  
**Target Roles**: Slaughterhouse Receiving Officers, Intake Supervisors.

---

## Purpose & Functionality
The Receiving module serves as the primary intake gatekeeper for incoming slaughter requests submitted via the mobile client. It triages requests between:
1. **Barangay Requests**: Livestock slated for local domestic consumption in specific barangays.
2. **Market Requests**: Commercial volume livestock slated for distribution in Tabaco City Public Market (subject to delivery van fees).

---

## Key Operations & Workflows
- **Approval Flow**: Sets `requests.status = 'approved'` and dispatches a notification to the client with their confirmed appointment date.
- **Capacity Management**: Displays real-time animal counts to prevent holding corral overcrowding.
- **Search & Filter**: Multi-parameter search by customer name, reference number (`MI-YYYY-XXX`), and intake date.

---

## Related Knowledge Links
- [[Table - requests]]
- [[Admin - Document Verification]]
- [[Flutter Admin Panel Architecture]]
