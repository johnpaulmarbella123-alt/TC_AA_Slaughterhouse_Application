---
title: "Discussion - Capstone Manuscript"
category: "Capstone Manuscript"
chapter: 5
created: 2026-09-26
last_updated: 2026-10-22
tags:
  - capstone
  - discussion
  - findings
  - conclusions
  - recommendations
---

# DISCUSSION

## Findings

Based on the empirical data gathered, full-stack architectural implementation on Supabase and Vercel, and stakeholder usability evaluations conducted for the Tabaco City "AA" Slaughterhouse, the findings are systematically organized in accordance with the Statement of the Problem (SOP):

### 1. Information Requirements & Core Modules (SOP 1):

- **Customer Portal and Remote Booking (SOP 1.a)**: The mobile application (`mobile_app`) successfully delivers sub-second scheduling and batch reservation capabilities for commercial meat dealers and backyard raisers. By allowing clients to specify livestock quantities and distribution destinations (*Barangay* vs. *Market*) remotely, pre-dawn receiving counter queues are completely eliminated.
- **Statutory Document & Permit Verification (SOP 1.b)**: Mobile image capture and upload direct to cloud storage buckets allow pre-arrival validation of Veterinary Health Certificates (VHC), Livestock Shipping Permits, and Barangay Clearances, ensuring that uncertified or suspect animals are stopped at the facility perimeter.
- **Holding Pen (Lairage) Triage & Queue Allocation (SOP 1.c)**: The administrative receiving console enforces real-time holding pen quotas, preventing corral overcrowding and maintaining humane animal welfare conditions in compliance with Republic Act No. 9296.
- **Ante-Mortem and Post-Mortem Clinical Inspection (SOP 1.d)**: Frontline meat inspectors utilize tablet logbooks to record clinical health diagnoses in holding pens and visceral pathology along dressing lines. Flagged carcasses instantly trigger legal Condemnation Slips (`CS-YYYY-XXX`), while wholesome carcasses advance to automated Meat Inspection Certificate (MIC) generation.
- **Municipal Billing, Cashiering, and Digital Payments (SOP 1.e)**: The integrated tariff engine computes fees based on certified net dressed carcass weights from calibrated digital scales. Cashiers process physical cash settlements with automated change calculation or verify cashless GCash payments via PayMongo, instantly issuing official receipts (`RCP-YYYY-XXX`).
- **Statutory Reporting and Illegal Slaughter Whistleblower Enforcement (SOP 1.f)**: The administrative dashboard compiles legal-size (8.5" × 14") Daily Slaughterhouse Production Reports formatted to NMIS standards. Concurrently, the citizen whistleblower module successfully routes geotagged reports and photo evidence of illegal slaughter to veterinary enforcement officers.

---

### 2. Automated Traceability Tools & Stock/Corral Tracking (SOP 2):

- **Livestock Lifecycle State Machine**: Every animal intake follows a strictly enforced, unidirectional lifecycle state progression (`pending_intake` $\rightarrow$ `approved` $\rightarrow$ `doc_verified` $\rightarrow$ `ante_passed` $\rightarrow$ `releasable` $\rightarrow$ `paid` $\rightarrow$ `completed`).
- **Biosecurity Quarantine Isolation**: Animals failing ante-mortem examination are locked out of the slaughtering hall, generating mandatory quarantine and incineration disposal orders that prevent biological contamination.
- **Perpetual Lairage Capacity Tracking**: Automated head count deductions and daily cutoff times (15:00 PM) maintain optimal holding pen densities, ensuring compliance with NMIS and DA humane livestock handling protocols.

---

### 3. Reporting, Billing, and Municipal Analytics (SOP 3):

- **Executive Real-Time Dashboards**: Management gains instantaneous visibility into daily intake volumes, species breakdowns (Hog, Cattle, Carabao, Goat), condemned carcass tallies, and gross municipal revenue inflows.
- **Tamper-Evident Fiscal Auditing**: Capturing atomic cashier shift balances, physical cash tendered, change calculations, and PayMongo payment references eliminates revenue leakage and drawer shortages.
- **Statutory Legal PDF Compilation**: The `ReportPdfGenerator` utility automates the generation of official NMIS Daily Slaughterhouse Production Reports, reducing monthly compliance compilation from three days to under five seconds.

---

### 4. Workplace Coordination & Resource Utilization (SOP 4):

- **Role-Tailored Operational Views**: Granular Role-Based Access Control (RBAC) securely confines receiving clerks to triage, inspectors to clinical examinations, cashiers to billing, and administrators to system governance.
- **Real-Time State Synchronization**: WebSocket broadcasting via Supabase Realtime delivers instant cross-station updates between holding pens, dressing rails, and the cashier desk, reducing intra-facility communication latency by over 75%.
- **Contactless Gate Pass Dispatch**: Cryptographically signed QR tokens scanned at the loading dock ensure that only certified, fully paid meat batches can exit through the municipal security gate.

---

### 5. Usability, Reliability, and Functionality Evaluation (SOP 5):

- **System Usability Scale Evaluation ($N = 46$)**: Achieved an exceptional composite score of **86.60 / 100** (Grade A+, "Excellent / Highly Usable"), with Usability at **88.00** and Learnability at **85.88**.
- **System Reliability & Concurrency**: The cloud-hosted PostgreSQL 15 database sustained zero data corruption, race conditions, or lost transactions during concurrent simulated load testing.
- **Functional Completeness**: The platform achieved 100% functional completeness across all 22 master use cases, validating the architectural suitability of the Flutter and Supabase technology stack for municipal abattoir management.

---

## Conclusions

Based on the empirical findings, full-stack architectural implementation on Supabase and Vercel, and psychometric usability evaluation of the Operation Management Application for AA Slaughterhouse of Tabaco City, the researchers draw the following definitive conclusions:

Information Architecture and Statutory Compliance. The transition from fragmented, paper-based ledgers to a centralized relational database architecture powered by PostgreSQL 15 and Supabase BaaS is indispensable for achieving operational transparency and regulatory compliance in municipal slaughterhouses. Capturing atomic animal arrival parameters, digital health permits, clinical ante/post-mortem diagnoses, calibrated carcass weights, and automated municipal fee assessments effectively eliminates lost records, human calculation errors, and delays in issuing official Meat Inspection Certificates (MIC), ensuring strict adherence to Republic Act No. 9296.

Decoupled Cloud Multi-Platform Architecture. The implementation of a decoupled, role-tailored software architecture—combining a cross-platform Flutter native mobile client for citizen customers with a desktop/web management console for abattoir staff and inspectors—successfully eliminates receiving counter bottlenecks and modernizes livestock inspection tracking. Decoupling operational interfaces allows distinct user groups (receiving clerks, meat inspectors, revenue cashiers, abattoir managers, and commercial meat dealers) to execute specialized workflows with maximum velocity, ergonomic ease, and zero data collisions.

High Usability Acceptance and Transformative Municipal Impact. The System Usability Scale (SUS) composite score of 86.60 (Grade A+, "Excellent") proves that the developed system achieves outstanding usability, low cognitive load, and high stakeholder acceptance across all user tiers. By providing intuitive, task-focused interfaces—such as minimal-tap mobile booking, visual slaughter line progress trackers, automated municipal fee computation, and one-click NMIS production PDF export—the system successfully reduces transaction turnaround times, eliminates revenue leakages, and establishes the Tabaco City Slaughterhouse as a model of digital public service excellence.

---

## Recommendations

Based on the empirical findings, architectural implementation, and operational evaluation of the Operation Management Application for AA Slaughterhouse of Tabaco City, the researchers propose the following actionable recommendations:

1. **Structured Onboarding and Continuous Training Programs**: Formal training programs should be established for abattoir receiving clerks, licensed veterinary meat inspectors, and revenue cashiers. Training should specifically reinforce standard operating procedures for digital permit verification, mobile ante-mortem and post-mortem clinical tagging, cash drawer float balancing, and ESC/POS thermal receipt printing.
2. **Workstation Hardware and Peripheral Provisioning**: Frontline abattoir receiving and cashiering desks should be provisioned with dedicated commercial hardware peripherals, including 80mm ESC/POS thermal receipt printers, RJ11-triggered automated cash drawers, high-speed 1D/2D optical barcode scanners, and heavy-duty laser printers supporting legal-size (8.5" × 14") statutory reports. In addition, floor meat inspectors should be outfitted with ruggedized Android tablets to facilitate real-time clinical logging and weighing directly within holding pens and slaughter bays.
3. **Power Grid and Network Infrastructure Resilience**: Uninterruptible Power Supply (UPS) units and backup network failover mechanisms should be deployed to safeguard continuous operations against municipal power grid fluctuations or localized ISP internet outages in Tabaco City. Equipping administrative workstations with dedicated battery backups alongside configuring dual-WAN or cellular 4G/5G mobile gateways will ensure uninterrupted cloud database connectivity.
4. **Institutional LGU Policy Adoption**: The Sangguniang Panlungsod and the Office of the City Mayor of Tabaco City should formally enact an enabling municipal ordinance designating the Operation Management Application as the official operational and revenue management system of the Tabaco City "AA" Slaughterhouse.
5. **Mandatory Administrative Auditing Routines**: Mandatory administrative routines should be enforced for the daily auditing of generated NMIS production reports, cash drawer reconciliations, and whistleblower tip logs. Abattoir management should periodically review Role-Based Access Control (RBAC) permission matrices to uphold the principle of least privilege across all user tiers.

---

## Areas for Further Studies

To build upon the foundations established by this capstone research, future researchers and software developers may explore the following technical extensions:

1. **Artificial Intelligence for Automated Carcass Grading and Pathology Detection**: Future research should investigate the integration of deep learning computer vision models (such as YOLOv8 or Convolutional Neural Networks) trained on livestock pathology image datasets. Integrating real-time camera inference along the evisceration line will assist meat inspectors in identifying organ lesions, swine fever symptoms, and carcass fat-to-lean marbling scores with automated diagnostic suggestions.
2. **IoT Load Cells and Automated Overhead Rail Weighing**: Subsequent studies should explore the deployment of Internet of Things (IoT) load cells and RFID/BLE transponders along the overhead conveyor rails. Integrating smart weight-sensing telemetry with the central database will enable automated, continuous carcass weighing without manual scale entry.
3. **Offline Synchronization and Conflict-Free Replicated Data Types (CRDTs)**: Future iterations of the system should develop local SQLite caching and peer-to-peer synchronization protocols using Conflict-Free Replicated Data Types (CRDTs) to ensure uninterrupted clinical logging in steel-reinforced abattoir cold storage rooms where wireless signals are completely obstructed.
4. **National DA-NMIS Meat Traceability Interoperability**: Future researchers should develop secure RESTful API integrations connecting the Tabaco City Slaughterhouse platform directly to the national Department of Agriculture - National Meat Inspection Service (DA-NMIS) central database for seamless cross-provincial livestock shipping verification and digital Meat Inspection Certificate (MIC) validation.
