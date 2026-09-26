---
title: "Admin - Slaughter & Inspection"
category: "Module Reference"
created: 2026-09-26
last_updated: 2026-09-26
tags:
  - module
  - admin
  - slaughter
  - inspection
  - veterinary
---

# Admin Module: Slaughter & Inspection

**Source File**: `admin_panel/lib/screens/slaughter_inspection_page.dart`  
**Target Roles**: City Veterinarians, National Meat Inspection Service (NMIS) Accredited Meat Inspectors.

---

## Purpose & Functionality
The core operational heart of the abattoir, managing physical livestock processing through distinct veterinary milestones:
1. **Ante-Mortem Inspection**: Physical evaluation of live animals in corrals for zoonotic diseases, fever, lethargy, or signs of cruelty.
2. **Slaughter Process Stages**:
   - Stunning (Humane pneumatic/electrical captive bolt)
   - Bleeding / Exsanguination
   - Scalding & Dehairing / Flaying
   - Evisceration & Splitting
3. **Post-Mortem Inspection**: Examination of visceral organs (lungs, heart, liver, intestines) and carcass lymph nodes for pathological lesions.
4. **Carcass Weighing & Release Authorization**: Logging official dressed weight in kilograms for tariff calculation.

---

## Key Operations & Workflows
- **Pass Post-Mortem**: Logs `carcass_weight`, assigns inspector name, updates `requests.status = 'releasable'`, and initializes a row in `payments`.
- **Condemnation (Partial/Total)**: Flags `post_mortem = 'Condemned'`, logs pathological reason, and dispatches condemnation notification to client.

---

## Related Knowledge Links
- [[Table - slaughter_inspection]]
- [[Table - payments]]
- [[Admin - Payment & Cashiering]]
