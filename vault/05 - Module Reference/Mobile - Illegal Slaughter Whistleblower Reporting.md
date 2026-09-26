---
title: "Mobile - Illegal Slaughter Whistleblower Reporting"
category: "Module Reference"
created: 2026-09-26
last_updated: 2026-09-26
tags:
  - module
  - mobile
  - whistleblower
  - enforcement
---

# Mobile Module: Illegal Slaughter Whistleblower Reporting

**Source File**: `mobile_app/lib/screen/report_illegal_slaughter_screen.dart`  
**Target Roles**: General Public, Concerned Citizens, Meat Consumers.

---

## Purpose & Functionality
Empowers the community to report illegal, clandestine slaughtering operations, uninspected meat selling, or hot meat ("botcha") distribution directly to the City Veterinary Office.

---

## Key Reporting Capabilities
1. **Anonymous Reporting Toggle**: Allows citizens to submit tips without linking their `user_id` or name for whistleblower protection.
2. **GPS Geolocation & Address**: Captures location coordinates or descriptive landmarks.
3. **Photo Evidence Capture**: Integrates `image_picker` to upload photographic evidence directly to the `report-evidence` storage bucket.
4. **Realtime Case Status**: Citizens can track whether their report is *Under Investigation* or *Resolved*.

---

## Related Knowledge Links
- [[Table - reports (Illegal Slaughter)]]
- [[Admin - Illegal Slaughter Oversight]]
- [[Storage Buckets & Asset Management]]
