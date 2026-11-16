# Manuscript Audit & Complete "Features of the Proposed System" Draft
**Project Title:** *Operation Management Application for AA Slaughterhouse of Tabaco City*

---

## PART I: Audit of Missing, Blank, and Mismatched Parts in the Current Manuscript (149-Page PDF)

### 1. Missing Body Section (Critical)
- **"Features of the Proposed System" (PDF pp. 53–54 / Manuscript pp. 38–39):**
  - Currently contains only two introductory paragraphs (`Features of the Proposed System` and `Mobile Application Features (Customer Side)`) before jumping straight to `System Design`.
  - **All 41 feature subsections and screenshots (Figures 3 to 43)** listed in the **List of Figures** (pp. xii–xiv) are missing from the body.
  - Note: Paragraph 2 under `Mobile Application Features (Customer Side)` on p. 38 incorrectly describes the mobile app as being for *"field inspectors, veterinary officers, and operational personnel on the abattoir processing floor"* — in the actual system, the **Mobile App is strictly the Customer Portal** (for livestock raisers, backyard owners, and meat dealers), while **Inspectors, Clerks, Cashiers, and Admins use the Admin & Operations Management Console** (Flutter Web/Desktop/Tablet).

### 2. Blank Tables & Missing Appendices
- **Table 8 – SUS Item Response Analysis (PDF p. 94 / Manuscript p. 79):** `Raw Mean`, `SD`, `Contribution`, and `Descriptive Interpretation` columns are **completely blank** (even though prose on p. 78 cites values like `4.67`, `4.65`, `4.62`, `1.39`, `1.43`).
- **Table 9 – Usability vs Learnability Subscale Breakdown (PDF p. 96 / Manuscript p. 81):** `Adjusted Factor Contribution`, `Rescale Score (0-100)`, and `Adjective Benchmark` are **completely blank** (prose cites `88.00` and `85.88`). Also contains a typo (`"Learnabilty"`) and mistakenly includes `Q4` in the Usability Scale row (p. 80 correctly assigns `Q4` to Learnability).
- **Table 10 – SUS Score Distribution by Stakeholder Group (PDF pp. 97–98 / Manuscript pp. 82–83):** `Mean SUS Score`, `Letter Grade`, `Adjective Rating`, and `Acceptability` are **completely blank** (prose cites `88.75`, `87.50`, `86.83`, `86.25`, `83.33`). Also typo `"Skateholder Stratum"`.
- **Appendix B – Data Dictionary (PDF pp. 128–134):**
  - `Table 4 (profiles)` has a duplicate `role` row (`ser role: ...`) and outdated column names (`full_name`, `phone_number` instead of actual `display_name`, `phone`, plus missing columns: `dealer_category`, `role_confirmed`, `municipality`, `barangay`, `market_name`, `stall_number`, `assigned_marking`, `marking_locked`, `is_active`, `deactivation_reason`, `role_document_url`).
  - `Table 5 (reports)` has broken headers (`Full Name | Data typer | Key / Nullable | Key / Nullable`) and row 1 (`id | created_at`).
  - Missing tables that exist in the live database: `notifications`, `system_settings`, `regular_dealers`.
- **Appendix C – Users' Manual, Section 6 "Getting Started & User Roles" (PDF p. 136 / Manuscript p. 121):** Contains a **completely blank 4-row table**.
- **Appendix G – System Usability Scale (PDF p. 143 / Manuscript p. 128):** Heading only; the 10-item SUS questionnaire instrument is missing.
- **Appendix I – Source Code (PDF p. 146 / Manuscript p. 131):** Heading only; no source code or repository link/extracts are included.

### 3. Formatting, Numbering, & Copy-Paste Errors
- **Objectives of the Study (PDF pp. 32–33 / Manuscript pp. 17–18):** Accidentally repeats the *Statement of the Problem* questions verbatim (`1. What innovative features... g. Customer Portal, h. Report or Complaint...`) instead of declarative objective statements (`"To design..."`, `"To develop..."`, `"To evaluate..."`).
- **Raw LaTeX Strings Leaked into Text:**
  - Manuscript p. 31: `1 = \text{Strongly Disagree}`, `i \in \{1, 3, 5, 7, 9\}`, `SUS = (ON + EN) \*2.5`
  - Manuscript p. 85: `pending_intake \rightarrow approved \rightarrow doc_verified...` (use `→` arrows).
- **Table of Contents & List of Figures Page Mismatches:** TOC/LOF page numbers (e.g., `System Design` p. 82, `User Acceptance Level` p. 120, `Figure 44` p. 85) do not match the actual pages (`System Design` is on p. 39, `Figure 44` on p. 41, `User Acceptance Level` on p. 76). Re-generate TOC and LOF after inserting Part II below.
- **In-Text Figure Number Mismatches:**
  - p. 42 refers to `Figure 6` (should be `Figure 45. Proposed System Flowchart`)
  - p. 46 refers to `Figure 21` (should be `Figure 46. Use Case Diagram`)
  - p. 49 refers to `Figure 22` (should be `Figure 47. Class Diagram`)
  - p. 52 refers to `Figure 23` and `Figure 10` (should be `Figure 48` & `Figure 49. Sequence Diagram`)
  - p. 55 refers to `Figure 24` and `Figure 12` (should be `Figure 50. Package Diagram`)
  - p. 57 refers to `Figure 8` (should be `Physical Design` figure)
  - p. 65 refers to `Figure 11` (should be `Figure 53. Deployment Diagram`)
- **Technical Discrepancies vs. Actual Codebase:**
  - Payment options in the live app are **PayMongo Online Payment** (GCash, Maya, GrabPay, Debit/Credit Card), **Cash on Pickup** (Barangay), and **Cash Over-the-Counter** (Market) — not GCash-only.
  - Meat Releasing verifies **Official Receipt Number (`RCP-YYYY-XXX`)**, **Authorized Person for Pickup / Valid ID** (for Barangay), or **Delivery Van Plate / Driver** (for Market) — not a 2D QR Gate Pass scanner or RJ11 cash drawer.
  - Printable receipts use **PDF Receipt Generation (`ReceiptPdfGenerator` + `Printing.layoutPdf`)** via browser/system print, rather than ESC/POS thermal printer commands.

---

## PART II: Complete Draft — "Features of the Proposed System"
*(Copy and paste directly into `RESULTS -> Features of the Proposed System` starting on Manuscript p. 38, replacing the placeholder paragraphs.)*

### Features of the Proposed System

The proposed **Operation Management Application for AA Slaughterhouse of Tabaco City** encompasses a comprehensive suite of integrated digital interfaces and functional modules designed to streamline livestock intake booking, statutory document verification, clinical veterinary inspection, municipal tariff billing, meat releasing, whistleblower enforcement, and administrative auditing. Built on a decoupled cloud architecture using Flutter and Supabase, the system's features are organized into two primary application environments: the **Customer Mobile Application (Portal)** for Android/iOS users and the **Administrative & Operations Management Console** for slaughterhouse personnel via Flutter Web/Desktop.

---

### A. Mobile Application Features (Customer Side)

The mobile-optimized component serves as the self-service **Customer Portal** for backyard livestock raisers, barangay residents, and commercial public market meat dealers. It replaces manual, pre-dawn in-person queuing with remote scheduling, real-time status tracking, cashless or over-the-counter settlement, digital receipt access, and citizen illegal slaughter reporting.

#### 1. User Registration & Account Onboarding
Customers create an account using their full name, email address or mobile phone number, and password, backed by Supabase Authentication and One-Time Password (OTP) verification. Account activation status (`is_active`) is enforced at sign-in and monitored in real time so deactivated or removed accounts are automatically signed out.

> **[Insert Figure 3: User Registration & Account Onboarding]**

#### 2. User Authentication & Login
Registered users sign in with either their email address or registered Philippine mobile phone number (`09XX` / `+639XX`) and password, or via Google Sign-In. Pre-login account status checks display clear feedback for unregistered accounts (`Account Not Registered`) or deactivated accounts before authentication completes.

> **[Insert Figure 4: User Authentication & Login]**

#### 3. Self-Service Password Recovery (Forgot Password with OTP)
When a customer forgets their password, the recovery flow becomes available as soon as an email or phone identifier is entered. Users verify their identity via a One-Time Password (OTP) sent to their registered email or phone and set a new password securely without administrative intervention.

> **[Insert Figure 5: Self-Service Password Recovery (Forgot Password with OTP)]**

#### 4. Interactive Home Dashboard
Upon login, the Home Dashboard displays a personalized greeting, quick-access action cards (**Request Schedule**, **Facility & Hygiene**, **How It Works**, **Report Illegal Slaughter**), active booking status summary, and official Tabaco City Slaughterhouse fee schedule reference.

> **[Insert Figure 6: Interactive Home Dashboard]**

#### 5. "How It Works" Educational Guide
An interactive step-by-step guide explains the complete slaughterhouse workflow—from choosing a permanent dealer role (Barangay or Market), uploading statutory permits, undergoing ante-mortem and post-mortem inspection, to paying municipal fees and claiming meat.

> **[Insert Figure 7: "How It Works" Educational Guide]**

#### 6. Facility & Hygiene Showcase Gallery
Customers can browse verified photos and descriptions of the Tabaco City Class "AA" Slaughterhouse facilities—including holding pens (lairage), sanitary slaughtering bays, overhead rail systems, cold storage rooms, and waste treatment—promoting public transparency and food safety confidence.

> **[Insert Figure 8: Facility & Hygiene Showcase Gallery]**

#### 7. Permanent Dealer Role Selection & Auto-Fill Onboarding
On their first booking, new customers select and permanently lock their dealer category—**Barangay** (backyard/community raisers) or **Market** (public market stallholders)—after confirming a role-lock notice:
- **Barangay Role:** Requires selecting their **City / Municipality** (Tabaco City and First District Albay municipalities: Bacacay, Malilipot, Malinao, Santo Domingo, Tiwi), dynamically loading the corresponding **Barangay** via PSGC, and uploading a **Barangay Certificate**.
- **Market Role:** Requires entering their **Market Name** and **Stall Number** and uploading a **Business Permit**.
Once confirmed, these details automatically populate future slaughter requests and immediately enroll the customer into the Admin **Meat Dealers Directory**.

> **[Insert Figure 9: Permanent Dealer Role Selection & Verification Card]**

#### 8. Slaughter Intake Schedule Booking Wizard
Customers submit remote slaughter bookings by selecting livestock species (**Pig/Hog**, **Cattle/Cow**, **Carabao**, **Goat**), entering head count, assigning their **Livestock Marking Tag**, choosing a preferred slaughter date, and confirming their location (PSGC Municipality/Barangay for Barangay orders, or auto-filled Market Name & Stall Number for Market orders).

> **[Insert Figure 10: Slaughter Intake Schedule Booking Wizard]**

#### 9. Statutory Document & Permit Upload Tool
The booking workflow captures and uploads high-resolution photos or files of mandatory statutory documents directly to Supabase Object Storage—**Barangay Certificate** / **Business Permit**, **Proof of Ownership**, and optional **Veterinary Health Certificate (VHC)**—with on-device **Google ML Kit Text Recognition (OCR)** support for reading permit details.

> **[Insert Figure 11: Statutory Document & Permit Upload Tool]**

#### 10. Booking Summary & Pre-Submission Review
Before final submission, customers review a consolidated summary of their livestock details, selected schedule, distribution channel, permanent marking tag, and uploaded documents, receiving a unique reference number (`MI-YYYY-XXX`) upon confirmation.

> **[Insert Figure 12: Booking Summary & Pre-Submission Review]**

#### 11. Real-Time Multi-Stage Request Tracking (Live Timeline)
Customers monitor their livestock's live progress across every facility stage (`Pending` → `Approved` → `Document Verified` → `Ante-Mortem` → `Slaughter Floor` → `Post-Mortem` → `Ready for Payment` → `Paid` → `Released`) via Supabase Realtime updates, without visiting the office counter.

> **[Insert Figure 13: Real-Time Multi-Stage Request Tracking (Live Timeline)]**

#### 12. Clinical Ante-Mortem Exception & Decision Handling
If an animal exhibits clinical signs or requires special handling during ante-mortem examination (such as immediate on-site slaughter at a separate facility or quarantine hold), the mobile tracker displays the veterinary advisory and required customer action in real time.

> **[Insert Figure 14: Clinical Ante-Mortem Exception & Decision Handling]**

#### 13. Official Digital Condemnation Slip Viewer (`CS-YYYY-XXX`)
When an animal or carcass is condemned during ante-mortem or post-mortem inspection under Republic Act No. 9296, customers can view the official **Digital Condemnation Slip** detailing the inspector's diagnosis, affected organs, severity, and disposal confirmation.

> **[Insert Figure 15: Official Digital Condemnation Slip Viewer (`CS-YYYY-XXX`)]**

#### 14. Flexible Schedule Rescheduling
If a booking is rejected due to daily corral capacity limits or missed schedule slots, customers can directly reschedule to an available date from their notification or status screen without re-entering livestock and document details.

> **[Insert Figure 16: Flexible Schedule Rescheduling]**

#### 15. Itemized Municipal Tariff Invoicing
Once post-mortem inspection passes and certified net dressed carcass weight (kg) is recorded, the system computes an itemized municipal tariff breakdown—**Veterinary Health Certificate**, **Permit to Slaughter**, **Facility Fee**, **Corral Fee**, **Ante-Mortem Fee**, **Post-Mortem Fee (per kg)**, **Delivery Van Fee** (Market requests only), and any applicable **Missed Schedule**, **Overdue Payment**, or **Cold Storage** penalties.

> **[Insert Figure 17: Itemized Municipal Tariff Invoicing]**

#### 16. PayMongo Hosted Digital Payment Gateway
Customers can settle invoices online through the integrated **PayMongo Checkout** via **Supabase Edge Functions**, supporting **GCash**, **Maya**, **GrabPay**, and **Debit/Credit Card**, with automated payment status reconciliation upon returning to the app.

> **[Insert Figure 18: PayMongo Hosted Digital Payment Gateway]**

#### 17. Cash Payment Options (Cash on Pickup & Cash Over-the-Counter)
Customers preferring cash settlement select the channel tailored to their role:
- **Barangay Requests:** **Cash on Pickup** (settled at the slaughterhouse cashier prior to claiming meat).
- **Market Requests:** **Cash Over-the-Counter** (settled at the slaughterhouse cashier counter prior to delivery van dispatch).

> **[Insert Figure 19: Cash on Pickup & Cash Over-the-Counter Payment Options]**

#### 18. Official Digital Receipt (`RCP-YYYY-XXX`) & Meat Pickup Authorization
Upon payment confirmation, the mobile app issues the **Official Digital Receipt (`RCP-YYYY-XXX`)** showing the itemized fee breakdown, amount paid, zero balance, and payment method. For paid **Barangay** orders not yet picked up, the receipt displays the **Meat Pickup Authorization** card allowing the owner to designate an authorized representative (with relationship, contact number, and valid ID) to claim the carcass; this authorization card automatically disappears once the meat is released (`status = 'released'`).

> **[Insert Figure 20: Official Digital Receipt & Meat Pickup Authorization]**

#### 19. In-App Notification Center
A dedicated **Notifications** feed alerts customers in real time with distinct visual badges and icons for booking approvals, document verification, **Schedule Notices** (missed-schedule warnings and penalties), inspection outcomes, payment confirmations, meat pickup/delivery readiness, and illegal slaughter report acknowledgements/resolutions.

> **[Insert Figure 21: In-App Notification Center]**

#### 20. Customer Profile & Historical Records Ledger
Customers can view their account profile, locked dealer role, permanent livestock marking, and historical transaction records, as well as submit service ratings and feedback.

> **[Insert Figure 22: Customer Profile & Historical Records Ledger]**

#### 21. Citizen Whistleblower Reporting for Illegal Slaughter
Citizens can report suspected illegal/backyard slaughtering or hot meat trading by selecting a violation category, capturing photographic evidence, attaching GPS location coordinates/address, and toggling **Anonymous Mode** (which omits `user_id` from the report). Non-anonymous reporters receive mobile notifications when the administration **acknowledges** or **compiles/resolves** their case.

> **[Insert Figure 23: Citizen Whistleblower Reporting for Illegal Slaughter]**

---

### B. Administrative & Operations Management Console Features (Admin, Clerk, & Inspector Side)

The Flutter Web/Desktop **Admin & Operations Management Console** serves as the internal operational backbone of the Tabaco City Slaughterhouse, enforcing Role-Based Access Control (RBAC) across **Admin**, **Clerk**, and **Inspector** portals, with a unified **Staff Notification Bell** (deduplicated alerts and toggleable audio chime) across all operational modules.

#### 22. Staff Authentication & Role-Based Access Control (RBAC) Gateway
Staff members authenticate into dedicated operational workspaces governed by RBAC:
- **Admin:** Full access to Executive Dashboard, Receiving, Document Verification, Slaughter & Inspection, Payment & Cashiering, Meat Releasing, Reports & Records, and Settings.
- **Clerk:** Focused workspace for Clerk Operations Dashboard, Receiving & New Requests, Document Verification, Payment & Cashiering, and Meat Releasing.
- **Inspector:** Dedicated clinical workspace for Inspector Dashboard and Slaughter & Inspection.

> **[Insert Figure 24: Staff Authentication & Role-Based Access Control (RBAC) Gateway]**

#### 23. Executive, Clerk, & Inspector Command Dashboards
Role-tailored dashboards display real-time KPI cards, live workflow stage pipelines, recent activity feeds, and quick-search reference lookup:
- **Admin Dashboard:** Total revenue, livestock processed, average processing time, satisfaction rate, and 5-stage live workflow counts.
- **Clerk Dashboard:** 4 concise operational KPIs (*Pending Receiving — For review & tagging*, *Pending Doc Verification — Permits to verify*, *Pending Billing & Payment — Receipts & payments*, *Ready for Meat Release — Ready for release*) and interactive stage queue.
- **Inspector Dashboard:** 4 clinical KPIs (*Awaiting Ante-Mortem — For floor exam*, *In-Progress Slaughter — Pending post-mortem*, *Flagged / Awaiting Decision — Awaiting decision*, *Completed Inspections — Passed or condemned*) and active floor queue.

> **[Insert Figure 25: Executive, Clerk, & Inspector Command Dashboards]**

#### 24. Intake Triage & Queue Partitioning Console
Receiving clerks triage incoming online bookings partitioned into **Barangay** and **Market** queues, reviewing livestock species, head counts, origin locations, and marking tags, and approving or rejecting bookings based on daily facility schedules.

> **[Insert Figure 26: Intake Triage & Queue Partitioning Console]**

#### 25. Holding Pen Capacity & Corral Slot Allocation Manager
The Receiving console monitors daily corral/holding pen head-count quotas in real time against configurable capacity limits, preventing pen overcrowding and ensuring humane livestock handling compliance.

> **[Insert Figure 27: Holding Pen Capacity & Corral Slot Allocation Manager]**

#### 26. Walk-In Livestock Registration & Intake Handler
For walk-in raisers or dealers without prior mobile bookings, clerks can encode livestock intake directly at the gate (with PSGC Municipality/Barangay or Market details, marking assignment, and printable Walk-In Claim Stub PDF).

> **[Insert Figure 28: Walk-In Livestock Registration & Intake Handler]**

#### 27. Gate Document Verification & Physical Compliance Gateway
Upon animal arrival, clerks cross-reference physical animals and ear-tags/markings against uploaded digital permits (Barangay Certificate, Business Permit, Proof of Ownership, VHC) and either verify compliance to admit livestock into lairage or reject non-compliant entries.

> **[Insert Figure 29: Gate Document Verification & Physical Compliance Gateway]**

#### 28. Ante-Mortem Clinical Inspection Station & Corral Logbook
Licensed meat inspectors conduct corral-level ante-mortem examinations, recording clinical status (**Passed**, **Suspect**, **Failed**), **Immediate Slaughter (Separate Facility)** flags, and automated **Missed-Schedule Offense Tracking** (issuing a 1st-offense waived warning or a ₱500.00 repeat-offense wasted slot penalty).

> **[Insert Figure 30: Ante-Mortem Clinical Inspection Station & Corral Logbook]**

#### 29. Official Ante-Mortem & Post-Mortem Condemnation Engine
Animals or carcasses failing clinical inspection trigger official **Condemnation Slips (`CS-YYYY-XXX`)** logging veterinary diagnosis, affected organs, partial/total condemnation severity, and disposal instructions, while blocking condemned carcasses from billing or release.

> **[Insert Figure 31: Official Ante-Mortem & Post-Mortem Condemnation Engine]**

#### 30. Slaughter Floor Line Process Stage Tracking Board
Inspectors update live processing stages along the slaughter floor (**Holding Pen** → **Stunning** → **Bleeding** → **Scalding** → **Evisceration** → **Post-Mortem**), synchronizing progress instantly to the customer mobile tracker and clerk dashboards.

> **[Insert Figure 32: Slaughter Floor Line Process Stage Tracking Board]**

#### 31. Post-Mortem Viscera Examination & Carcass Weighing Station
Inspectors record post-mortem visceral findings (**Passed**, **Condemned**, **Retained**) and enter the certified net dressed carcass weight in kilograms, automatically calculating municipal slaughter fees and transitioning cleared batches to `releasable`.

> **[Insert Figure 33: Post-Mortem Viscera Examination & Carcass Weighing Station]**

#### 32. Meat Inspection Certificate (MIC) Generation Engine
For carcasses passing post-mortem inspection, inspectors generate and print official **Meat Inspection Certificates (MIC)** as formatted PDF documents via `InspectionDocumentsPdfGenerator` and `Printing.layoutPdf`.

> **[Insert Figure 34: Meat Inspection Certificate (MIC) Generation Engine]**

#### 33. Municipal Tariff Billing & Cashiering Workspace
Clerks and cashiers view itemized invoices for Barangay and Market orders, inspect PayMongo online payment status (with live PayMongo link verification), send digital invoices to customers, and distinguish unpaid **Cash on Pick-up** (Barangay) vs. **Cash Over-the-Counter** (Market) statuses.

> **[Insert Figure 35: Municipal Tariff Billing & Cashiering Workspace]**

#### 34. Official Receipt Issuance & Printable PDF Receipt Generator
Upon confirming PayMongo or cash settlement, the system issues an Official Receipt (`RCP-YYYY-XXX`) and allows staff to print a formatted A4 **Payment Receipt PDF** (`ReceiptPdfGenerator`) matching the exact itemized fee breakdown, customer/livestock details, cashier name, and payment status.

> **[Insert Figure 36: Official Receipt Issuance & Printable PDF Receipt Generator]**

#### 35. Meat Releasing & Dispatch Verification
Clerks verify paid orders prior to physical handover—checking Receipt Number (`RCP-YYYY-XXX`), **Authorized Person for Pickup / Valid ID** for Barangay pickups, or **Delivery Van / Driver** details for Market deliveries, collecting any remaining ₱150.00 Cold Storage overdue fee if applicable, and recording the immutable `released_at` timestamp.

> **[Insert Figure 37: Meat Releasing & Dispatch Verification]**

#### 36. Illegal Slaughter Whistleblower Case Investigation Desk
Administrators review citizen-submitted illegal slaughter reports (from both `reports` and `notifications`), inspect uploaded photo evidence and geolocation, assign triage severity, **Acknowledge** cases, dispatch investigation notes, and **Compile / Resolve** cases with enforcement agency endorsement (CVO, NMIS, PNP)—automatically notifying non-anonymous reporters on mobile.

> **[Insert Figure 38: Illegal Slaughter Whistleblower Case Investigation Desk]**

#### 37. Statutory Daily Production & NMIS PDF Report Generator
Management compiles daily, weekly, and monthly analytics and generates legal-size (`8.5" × 14"`) **NMIS Daily Slaughterhouse Production PDF Reports** (`ReportPdfGenerator` & `NmicReportPdfGenerator`) detailing species head counts, dressed carcass weights, condemnations, and municipal revenue.

> **[Insert Figure 39: Statutory Daily Production & NMIS PDF Report Generator]**

#### 38. Commercial Meat Dealers Directory & Registry Management
An automated **Meat Dealers Registry Table** (backed by `regular_dealers` and a PostgreSQL trigger on `profiles.role_confirmed`) immediately enrolls role-confirmed Barangay and Market customers—showing **`—`** for pending markings until their first request locks their self-assigned marking—alongside **Lifetime Heads** (with custom pig icon), contact details, status badges, and editable/exportable PDF directory support.

> **[Insert Figure 40: Commercial Meat Dealers Directory & Registry Management]**

#### 39. Master System Configuration, Capacity & Tariff Management
In **Settings**, administrators configure holding pen capacities, slaughter fee rates, operating schedules/cutoff times, NMIS officer signatories, and public advisories, all persisted in `system_settings`.

> **[Insert Figure 41: Master System Configuration, Capacity & Tariff Management]**

#### 40. Staff Account, Customer Account & Real-Time Notification Bell Console
Administrators manage internal staff RBAC accounts (**Admin**, **Clerk**, **Inspector**) and registered **Customer Accounts** (search, filter by Active/Deactivated, view role documents, view accurate request counts, deactivate with reason, or delete accounts—enforced live on mobile). A global **Staff Notification Bell** across all operational pages provides deduplicated real-time alerts with an optional audio chime and one-click navigation.

> **[Insert Figure 42: Staff Account, Customer Account & Notification Console]**
