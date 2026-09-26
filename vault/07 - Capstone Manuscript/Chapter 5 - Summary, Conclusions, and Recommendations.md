---
title: "Chapter 5 - Summary, Conclusions, and Recommendations"
category: "Capstone Manuscript"
chapter: 5
created: 2026-09-26
last_updated: 2026-09-26
tags:
  - capstone
  - chapter-5
  - summary
  - conclusions
  - recommendations
---

# Chapter 5: Summary, Conclusions, and Recommendations

This chapter synthesizes the primary findings of the study, presents definitive conclusions derived from the development and empirical evaluation of the system, outlines actionable recommendations for municipal stakeholder adoption, and identifies promising technical extensions for future research.

---

## Summary of Findings

Based on the empirical data gathered, architectural implementation results, and psychometric usability evaluations conducted for the **Operation Management Application for AA Slaughterhouse of Tabaco City**, the findings of this study are summarized as follows:

1. **Information Architecture & Data Integration (SOP 1 & SOP 2)**:
   - The transition from fragmented, paper-based ledgers to a centralized PostgreSQL database on Supabase established full operational transparency and data integrity across the Tabaco City Slaughterhouse.
   - Capturing livestock specifications, statutory permit images (Veterinary Health Certificates, Shipping Permits), clinical ante/post-mortem inspection findings, net dressed carcass weights, and municipal fee payments into normalized relational tables eliminated record loss, calculation errors, and inspection delays.

2. **Decoupled Architecture & Multi-Platform Implementation (SOP 3 & SOP 4)**:
   - The implementation of a decoupled, role-tailored software architecture—combining a cross-platform Flutter native mobile client for citizen customers with a desktop/web management console for abattoir staff—eliminated intake counter bottlenecks and modernized inspection tracking.
   - Integration with serverless Deno Edge Functions and the PayMongo API enabled secure, automated GCash payment links and instant transaction verification, completely eliminating manual screenshot reviews and unverified payments.
   - The automated PDF reporting service successfully compiled legal-size (8.5" x 14") Daily Slaughterhouse Production Reports adhering to official National Meat Inspection Service (NMIS) formats.

3. **High Usability & Stakeholder Acceptance (SOP 5)**:
   - Post-implementation evaluation using the standardized System Usability Scale (SUS) across $N = 46$ representative stakeholders (administrators, veterinary inspectors, receiving clerks, butchers, and meat dealers) yielded an exceptional composite score of **86.60 / 100** (Grade A+, "Excellent / Highly Usable").
   - Subscale psychometric factor analysis revealed high performance in both routine interaction usability (88.00) and rapid learnability (85.88), demonstrating that the system can be operated effectively by frontline staff with minimal formal technical training.

---

## Conclusions

Based on the empirical findings, full-stack architectural implementation, and psychometric usability evaluations, the researchers draw the following definitive conclusions:

1. **Achievement of Project Objectives**: All five specific research objectives established in the Statement of the Problem were successfully accomplished, delivering a functional, secure, and compliant slaughterhouse management software suite.
2. **Operational Efficiency & Workflow Modernization**: The application replaces labor-intensive, error-prone manual methods with streamlined digital workflows, accelerating livestock receiving, veterinary inspection tagging, fee collection, and meat dispatching.
3. **Strict Regulatory Compliance & Food Safety**: By automating Meat Inspection Certificate (MIC) generation, condemnation slip issuance, and carcass weight logging, the platform reinforces strict compliance with Republic Act No. 9296 (The Meat Inspection Code of the Philippines) and NMIS food safety mandates.
4. **Fiscal Integrity & Revenue Transparency**: The automated tariff calculation engine and digital GCash payment integration eliminate revenue leakage, unrecorded cash discrepancies, and unauthorized fee adjustments, providing an auditable financial trail for the Local Government Unit of Tabaco City.
5. **Replicable Blueprint for Local Government Modernization**: The study delivers a validated, scalable, and cost-effective digital modernization blueprint that can be replicated by other LGU-managed abattoirs across the Bicol Region and nationwide.

---

## Recommendations

Based on the empirical findings, architectural implementation, and operational evaluation of the system, the researchers propose the following actionable recommendations:

1. **Structured Onboarding & Continuous Training Programs**:
   - Establish formal training workshops for abattoir receiving clerks, veterinary meat inspectors, and revenue cashiers. Training should specifically reinforce standard operating procedures for digital permit verification, clinical disease tagging, cash drawer balancing, and ESC/POS thermal receipt printing.

2. **Workstation Hardware & Peripheral Provisioning**:
   - Provision frontline abattoir workstations with commercial hardware peripherals, including 80mm ESC/POS thermal receipt printers, RJ11-triggered automated cash drawers, high-speed 1D/2D optical barcode scanners, and high-speed laser printers supporting legal-size (8.5" x 14") statutory documents.
   - Outfit abattoir meat inspectors and floor handlers with ruggedized Android tablets or handheld mobile scanners to facilitate real-time clinical logging and weighing directly within the holding corrals and slaughter line bays.

3. **Power Grid & Network Infrastructure Resilience**:
   - Deploy Uninterruptible Power Supply (UPS) battery units and dual-WAN or cellular 4G/5G mobile failover gateways at the slaughterhouse facility to safeguard continuous operations against municipal power grid fluctuations or localized ISP internet outages.

4. **Institutional LGU Policy Adoption**:
   - The Sangguniang Panlungsod and the Office of the City Mayor of Tabaco City should formally enact an enabling municipal ordinance designating the application as the official operational management system of the Tabaco City Slaughterhouse.

5. **Routine Administrative Auditing**:
   - Enforce mandatory administrative routines for the daily review of generated production reports, cash drawer reconciliations, and whistleblower tip logs. Periodically review Role-Based Access Control (RBAC) permission matrices to uphold the principle of least privilege across all user tiers.

---

## Areas for Further Studies

To build upon the foundations established by this capstone research, future researchers and software developers may explore the following technical extensions:

1. **Artificial Intelligence for Automated Carcass Grading & Pathology Detection**:
   - Investigate the integration of deep learning computer vision models (e.g. YOLOv8 or Convolutional Neural Networks) trained on livestock pathology image datasets. Integrating real-time camera inference will assist meat inspectors in identifying organ lesions, swine fever symptoms, and carcass fat-to-lean marbling scores with automated diagnostic suggestions.

2. **IoT Load Cells & Automated Overhead Rail Weighing**:
   - Explore the deployment of Internet of Things (IoT) load cells and RFID/BLE transponders along the overhead conveyor rails. Integrating smart weight-sensing telemetry with the central database will enable automated, continuous carcass weighing without manual scale entry.

3. **Offline Synchronization & Conflict-Free Replication (CRDTs)**:
   - Develop local SQLite caching and peer-to-peer synchronization protocols using Conflict-Free Replicated Data Types (CRDTs) to ensure uninterrupted clinical logging in steel-reinforced abattoir cold storage rooms where wireless signals are completely obstructed.

4. **National DA-NMIS Meat Traceability Interoperability**:
   - Develop secure RESTful API integrations connecting the Tabaco City Slaughterhouse platform directly to the national Department of Agriculture - National Meat Inspection Service (DA-NMIS) central database for seamless cross-provincial livestock shipping verification and digital Meat Inspection Certificate (MIC) validation.
