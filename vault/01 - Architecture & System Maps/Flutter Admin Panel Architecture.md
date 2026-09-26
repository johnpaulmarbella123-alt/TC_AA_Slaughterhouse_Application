---
title: "Flutter Admin Panel Architecture"
category: "Architecture"
created: 2026-09-26
last_updated: 2026-09-26
tags:
  - admin
  - flutter
  - desktop
  - web
---

# Flutter Admin Panel Architecture

The **Admin Panel Application** (`admin_panel`) is the management backbone of the slaughterhouse operations. It is designed for desktop and web interfaces, serving receiving officers, veterinary meat inspectors, cashier personnel, and slaughterhouse administrators.

---

## Source Code Structure (`admin_panel/lib`)

```
admin_panel/lib/
├── main.dart                               # App entry point, Supabase auth check, route definitions
├── theme.dart                              # Design tokens, color palette (#2D6A4F primary), typography
├── pages/
│   ├── login_page.dart                     # Admin authentication with "Keep me logged in" toggle
│   └── signup_page.dart                    # Admin account provisioning
├── screens/
│   ├── admin_shell.dart                    # Navigation container with sidebar layout & routing
│   ├── dashboard.dart                      # High-level metrics, daily throughput, revenue KPIs
│   ├── hero_section.dart                   # Public landing view
│   ├── receiving_requests_page.dart        # Intake approval (Barangay / Market tabbed queues)
│   ├── document_verification_page.dart     # Permit examination (Vet cert, shipping permit check)
│   ├── slaughter_inspection_page.dart      # Ante/Post-mortem inspection, stage tagging, carcass weights
│   ├── payment_cashiering_page.dart        # Tariff calculator, fee collection, receipt issuance
│   ├── meat_releasing_page.dart            # Pickup verification, gate pass check, release logging
│   ├── reports_records_page.dart           # Daily, weekly, monthly aggregation & export UI
│   └── illegal_slaughter_reports_view.dart # Citizen whistleblower incident investigation console
└── services/
    └── report_pdf_generator.dart           # Government legal-format PDF document compiler
```

---

## Navigation & Module Routing

The admin portal utilizes a Shell-and-Subpage architecture:
1. **`AdminShell` Widget**:
   - Manages the active view state (`_selectedIndex`).
   - Renders a 280px left sidebar (`_AdminSidebar`) when a sub-module is active.
   - When viewing index 0 (`DashboardPage`), the sidebar collapses to present a full-width analytics screen.
2. **Tabbed Workflow Navigation**:
   - Module 1: Receiving & Intake (`ReceivingRequestsPage`)
   - Module 2: Document Verification (`DocumentVerificationPage`)
   - Module 3: Slaughter & Inspection (`SlaughterInspectionPage`)
   - Module 4: Payment & Cashiering (`PaymentCashieringPage`)
   - Module 5: Meat Releasing (`MeatReleasingPage`)
   - Module 6: Reports & Records (`ReportsRecordsPage`)
   - Module 7: Illegal Slaughter Reports (`IllegalSlaughterReportsView`)

---

## Centralized Fee Calculation Engine

In `payment_cashiering_page.dart`, fees are computed strictly according to city slaughterhouse ordinances:

```dart
// Municipal Slaughterhouse Tariff Schedule
const double _kVetHealthCertFee   = 50.0;
const double _kPermitToSlaughterFee= 60.0;
const double _kFacilityFee         = 60.0;
const double _kCorralFee           = 40.0;
const double _kAnteMortemFee       = 40.0;
const double _kPostMortemRatePerKg = 5.0;  // ₱5.00 per kg of carcass weight
const double _kDeliveryVanFee      = 60.0; // Applicable for Market requests only
```

$$\text{Total Fee} = \text{VetCert} + \text{Permit} + \text{Facility} + \text{Corral} + \text{AnteMortem} + (\text{Weight}_{\text{kg}} \times 5.00) + [\text{DeliveryVan}_{\text{Market}}]$$

---

## PDF Document Generation Pipeline

The `ReportPdfGenerator` compiles raw database rows into an official **Daily Slaughterhouse Production Report** using the `pdf` and `printing` packages.
- **Page Format**: `PdfPageFormat.legal` (8.5 x 14 inches) matching Philippine LGU standard document size.
- **Visual Structure**: Government Republic seal, Tabaco City header, dual Market/Barangay livestock tables, animal count summaries (Hogs, Cattle, Carabao, Goat), and official inspector signature blocks.

---

## Related Knowledge Links
- [[PDF Generation & Document Lifecycle]]
- [[Admin - Slaughter & Inspection]]
- [[Admin - Payment & Cashiering]]
- [[Admin - Reports & Records]]
