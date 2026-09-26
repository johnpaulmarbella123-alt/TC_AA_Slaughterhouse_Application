---
title: "Admin - Reports & Records"
category: "Module Reference"
created: 2026-09-26
last_updated: 2026-09-26
tags:
  - module
  - admin
  - reports
  - analytics
  - pdf
---

# Admin Module: Reports & Records

**Source File**: `admin_panel/lib/screens/reports_records_page.dart`  
**Target Roles**: City Slaughterhouse Administrator, City Veterinarian, LGU Internal Auditors.

---

## Purpose & Functionality
Aggregates historical and daily operational data for statutory reporting, revenue auditing, and municipal performance metrics.

---

## Report Types & Export Capabilities
1. **Daily Slaughterhouse Production Report**:
   - Compiles all processed livestock for the selected date into a legal-size PDF (`ReportPdfGenerator`).
   - Details owner names, animal counts, live weights, carcass weights, and fee breakdowns.
   - Summarizes total heads by species (Hogs, Cattle, Carabao, Goats).
2. **Revenue Summary**:
   - Aggregates daily, weekly, and monthly fee collections (Cash vs GCash).
3. **Veterinary Condemnation Logbook**:
   - Records total condemned carcass weight and disease diagnoses for epidemiology tracking.

---

## Related Knowledge Links
- [[PDF Generation & Document Lifecycle]]
- [[Flutter Admin Panel Architecture]]
