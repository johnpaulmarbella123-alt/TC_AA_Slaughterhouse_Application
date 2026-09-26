---
title: "Mobile - Inspection Tracking & Condemnation Slips"
category: "Module Reference"
created: 2026-09-26
last_updated: 2026-09-26
tags:
  - module
  - mobile
  - tracking
  - condemnation
---

# Mobile Module: Inspection Tracking & Condemnation Slips

**Source Files**: `mobile_app/lib/pages/home_page.dart` & `mobile_app/lib/screen/condemnation_slip_screen.dart`  
**Target Roles**: Meat Dealers, Hog Raisers, Meat Buyers.

---

## Purpose & Functionality
Provides real-time visibility into the physical processing status of livestock batches and instant issuance of legal condemnation notices if animals fail veterinary standards.

---

## Features
1. **Live Visual Timeline**:
   - `Intake Approved`  `Doc Verified`  `Slaughtering`  `Releasable / Ready for Payment`  `Meat Released`.
2. **Digital Condemnation Certificate**:
   - In the event of pathology detection (*Swine Fever*, *Cysticercosis*, *Jaundice*), the app renders an official digital **Condemnation Slip** (`CS-YYYY-XXX`) containing the certifying inspector's license and disposal instructions.

---

## Related Knowledge Links
- [[Table - slaughter_inspection]]
- [[Admin - Slaughter & Inspection]]
- [[PDF Generation & Document Lifecycle]]
