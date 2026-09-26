---
title: "Capstone Preliminaries - Operation Management Application for AA Slaughterhouse of Tabaco City"
category: "Capstone Manuscript"
institution: "Polytechnic Institute of Tabaco"
degree: "Bachelor of Science in Information Technology"
authors:
  - "Melch John Paul B. Marbella"
  - "Andrie B. Barasona"
  - "Jonathan M. Bino"
adviser: "Tom Justine B. Militante, MPM"
date: "December 2025"
tags:
  - capstone
  - preliminaries
  - thesis
---

# Operation Management Application for AA Slaughterhouse of Tabaco City

A Capstone Project Presented to the Faculty of Computer Studies  
Department of Polytechnic Institute of Tabaco  
100 Panal, Tabaco City  

In Partial Fulfillment of the Requirements for the Degree of  
Bachelor of Science in Information Technology  

**Researchers / Proponents:**  
Marbella, Melch John Paul B.  
Barasona, Andrie B.  
Bino, Jonathan M.  

**Date:**  
December 2025  

---

## Recommendation for Final Defense

This thesis titled **"OPERATION MANAGEMENT APPLICATION FOR AA SLAUGHTERHOUSE OF TABACO CITY"** prepared by **Melch John Paul B. Marbella**, **Andrie B. Barasona**, and **Jonathan M. Bino**, in partial fulfillment of the requirements for the degree of Bachelor of Science in Information Technology (BSIT) is hereby submitted to the Thesis Committee for appropriate action.

**TOM JUSTINE B. MILITANTE, MPM**  
Adviser  

---

## Certification of Final Rating

**Candidates:** Melch John Paul B. Marbella, Andrie B. Barasona, Jonathan M. Bino  
**Thesis:** OPERATION MANAGEMENT APPLICATION FOR AA SLAUGHTERHOUSE OF TABACO CITY  

### Panel of Oral Examiners

| Name | Designation | Signature | Action |
| :--- | :--- | :--- | :--- |
| **JAIME Ll. GUARDINO** | Panel Member | `[Signed]` | Passed |
| **MARILOU S. BENOZA-LANSANGAN, MM, MIT, DIT** | Chairperson | `[Signed]` | Passed |
| **JP REMAR A. SERRANO, MIS** | Panel Member | `[Signed]` | Passed |

**Final Rating:** `[Passed]`  

---

## Approval Sheet

This project study titled **"OPERATION MANAGEMENT APPLICATION FOR AA SLAUGHTERHOUSE OF TABACO CITY"**, was prepared and submitted by **Melch John Paul B. Marbella**, **Andrie B. Barasona**, and **Jonathan M. Bino**, in partial fulfillment of the requirements for the degree in Bachelor of Science in Information Technology, has been examined and recommended for acceptance and approval for final defense.

**TOM JUSTINE B. MILITANTE, MPM**  
Adviser & Capstone Project Coordinator  

**ELMER C. FIGURACION, MIT**  
Dean, College of Computer Studies  

**JAIME Ll. GUARDINO**  
President, Polytechnic Institute of Tabaco  

---

## Certification of Editor

This is to certify that the undergraduate thesis entitled **"OPERATION MANAGEMENT APPLICATION FOR AA SLAUGHTERHOUSE OF TABACO CITY"**, prepared and submitted by Melch John Paul B. Marbella, Andrie B. Barasona, and Jonathan M. Bino for the undergraduate research in Information Technology has been edited by the undersigned.

`__________________________`  
Language Editor  

---

## Acceptance Sheet

This thesis titled **"OPERATION MANAGEMENT APPLICATION FOR AA SLAUGHTERHOUSE OF TABACO CITY"**, after having been recommended and approved, is hereby accepted by the Polytechnic Institute of Tabaco.

**JAIME Ll. GUARDINO**  
President, Polytechnic Institute of Tabaco  

---

## Acknowledgement

The researchers sincerely thank everyone who contributed to their capstone project's success. This journey would not have been possible without countless individuals' invaluable support and assistance.

- **To the Capstone Adviser and Subject Instructor, Mr. Tom Justine Militante, MPM**: The researchers express their deep and sincere gratitude for guiding and correcting their manuscript whenever it was needed. Special thanks for ensuring the highest academic and technical rigor.
- **To Mr. Carl Jan Binalla**: Thank you for sharing your technical knowledge, offering constructive architectural suggestions, and providing motivation in completing the study.
- **To Dr. Kim Ronan Romeo of the Tabaco City Slaughterhouse**: Gratefully acknowledged for significant contributions, unwavering support, and commitment to this research. Her freely given time, operational knowledge, and domain information greatly advanced and improved the project's quality and results.
- **To the Polytechnic Institute of Tabaco**: The proponents are incredibly appreciative and humble toward the institution for allowing them to complete a capstone thesis project and enhance their engineering abilities.

**M.J.P.B.M.** | **A.B.B.** | **J.M.B.**

---

## Abstract

**Title**: Operation Management Application for AA Slaughterhouse of Tabaco City  
**Authors**: Melch John Paul B. Marbella, Andrie B. Barasona, Jonathan M. Bino  
**Type of Document**: Project Study (Undergraduate Thesis)  
**Accrediting Institution**: Polytechnic Institute of Tabaco, 100 Panal, Tabaco City  
**Adviser**: Tom Justine B. Militante, MPM  
**Year**: 2025  

### Introduction
In the global food supply chain, managing slaughterhouse operations using outdated manual processes leads to operational inefficiencies, inaccurate documentation, and delayed transactions. The Tabaco City Slaughterhouse experiences these specific challenges in meticulously maintaining records for slaughtering activities, inspection outcomes, and payment processing. This study focused on the development of an Integrated Web and Mobile-Based Slaughterhouse Management and Customer Portal System to digitize workflows, enable real-time monitoring, and improve efficiency, accuracy, and transparency for both management and customers.

### Methods
The study utilized the Rapid Application Development (RAD) methodology in developing an Operation Management Application for the AA Slaughterhouse of Tabaco City. Data were collected through interviews, questionnaires, surveys, and document analysis involving slaughterhouse staff, meat inspectors, management personnel, backyard farmers, and meat dealers. Purposive sampling was used to deliberately select participants ($n = 46$) directly involved in slaughterhouse operations. Additionally, the System Usability Scale (SUS) was utilized to evaluate the usability and effectiveness of the proposed system.

### Results
The system's identified information requirements effectively supported animal receiving, ante-mortem and post-mortem inspection monitoring, and record organization, which minimized manual errors and improved workflow efficiency. The implemented features, including the customer portal for slaughter schedule requests, real-time tracking, integrated billing mechanisms, and an illegal slaughter reporting tool, were found to be functional and responsive to stakeholder needs. Usability evaluations indicated high user acceptance (composite SUS score of 85.8 / 100, Grade A+), confirming the system's effectiveness in enhancing data accuracy, ensuring sanitation and regulatory compliance, and reducing the administrative workload.

### Conclusion
The study concluded that the Operation Management Application for the AA Slaughterhouse of Tabaco City successfully replaced manual processes, boosting the efficiency, accuracy, transparency, and accessibility of operations and customer services. For future impact, the system may serve as an exemplary model and blueprint for the digital modernization and transformation of other local government-managed slaughterhouses across the Philippines.

**Keywords**: Slaughterhouse Management, Web and Mobile System, Meat Inspection, Traceability, Automation, Usability, Flutter, Supabase, PayMongo.

---

## Table of Contents

- [[00 - Preliminaries|Preliminaries]]
  - Title Page
  - Recommendation for Final Defense
  - Certification of Final Rating
  - Approval Sheet
  - Certification of Editor
  - Acceptance Sheet
  - Acknowledgement
  - Abstract
  - Table of Contents
  - List of Figures
  - List of Tables
- [[Chapter 1 - Introduction|Chapter 1: Introduction]]
  - Background of the Study
  - Rationale of the Study
  - Company Profile (Tabaco City Slaughterhouse)
  - Significance of the Study
  - Statement of the Problem (SOP 1 to SOP 5)
  - Objectives of the Study (General & Specific)
  - Scope and Delimitation of the Study
  - Definition of Terms (Conceptual & Operational)
- [[Chapter 2 - Review of Related Literature and Technical Background|Chapter 2: Review of Related Literature and Technical Background]]
  - Review of Related Literature and Systems
  - Information Requirements Assessment
  - System Features and Functionality Analysis
  - Extent of System Usability
  - Summary of Literature
  - Conceptual Design Framework (Figure 2 IPO Diagram)
  - Technical Background & Software Development Methodology (Figure 3 RAD Model)
  - System Design & Software Architecture (Figure 4 Decoupled Multi-Tier / MVC)
  - Process Flowcharts (Figure 5 Existing Manual vs. Figure 6 Proposed System Flowchart)
  - System Use Case Analysis (Figure 7 Use Case Diagram with 5 Actor Tiers)
  - Physical Design & Deployment (Figure 8 Infrastructure Network)
  - Architectural Design (Figure 9 Multi-Tier Block Architecture)
  - System Execution Sequence (Figure 10 Sequence Diagram)
  - Deployment Architecture (Figure 11 Deployment Diagram)
  - Package Architecture (Figure 12 Package Diagram)
  - Object-Oriented Domain Model (Figure 13 Class Diagram)
  - Development Tools Used (Table 1)
  - Database and Data Management Architecture
  - Software & Hardware Requirements (Tables 2 & 3)
- [[Chapter 3 - Methodology|Chapter 3: Methodology]]
  - Sources of Data (Primary & Secondary)
  - Data Gathering Techniques (Interviews, Questionnaires, Surveys, Document Analysis)
  - Tools for Data Analysis (Excel, Google Forms, Looker Studio, SPSS 28)
  - Sampling Procedure (Purposive Sampling, $n = 46$)
  - System Usability Scale (SUS) Mathematical Formulation & Subscale Scoring
- [[Chapter 4 - Results and Discussion|Chapter 4: Results and Discussion]]
  - Information Requirements Analysis (Tables 4, 5, 6 for Sub-domains A, B, C)
  - System Features & Functional Specifications (Figures 14 to 29 Interface Walkthroughs)
  - User Acceptance Level (Tables 7, 8, 9, 10 SUS Item, Subscale, and Demographic Analysis)
  - Systematic Summary of Findings by SOP (SOP 1 to SOP 5)
- [[Chapter 5 - Summary, Conclusions, and Recommendations|Chapter 5: Summary, Conclusions, and Recommendations]]
  - Summary of Findings
  - Conclusions
  - Recommendations for Policy & Municipal Adoption
  - Areas for Further Studies (AI Carcass Grading, RFID Telemetry, Offline CRDT Sync)
- [[References|References (APA 7th Edition)]]
- [[Appendices|Appendices (A to G)]]
  - Appendix A: Formal Institutional Communication Letter
  - Appendix B: Master Technical Data Dictionary
  - Appendix C: System User's Manual Guide
  - Appendix D: Information Flow & DFD Diagrams
  - Appendix E: Project Implementation Gantt Chart
  - Appendix F: Key Stakeholder Interview Question Guide
  - Appendix G: System Usability Scale (SUS) Evaluation Instrument

---

## List of Figures

| Figure | Title | Description / Diagram Format |
| :--- | :--- | :--- |
| **Figure 1** | Geographic Location & Site Layout of Tabaco City AA Slaughterhouse | Facility Zoning & Corridor Map Diagram |
| **Figure 2** | Conceptual Design Diagram | Input-Process-Output (IPO) Framework |
| **Figure 3** | Rapid Application Development (RAD) Process Model | 4-Phase Iterative Lifecycle Diagram |
| **Figure 4** | Decoupled Multi-Tier Software Architecture | Model-View-Controller (MVC) Pattern |
| **Figure 5** | Existing Flowchart of Tabaco City Slaughterhouse | Manual Abattoir Process Flowchart |
| **Figure 6** | Proposed System Flowchart of Operation Management Application | Digital Workflow & Decision Gateway Flowchart |
| **Figure 7** | System Use Case Diagram | 5-Actor Use Case Interaction Model |
| **Figure 8** | Physical Design & Infrastructure Deployment Diagram | Network, Firewall, BaaS, & Peripheral Topology |
| **Figure 9** | Architectural Design of the Proposed System | Decoupled Three-Tier System Architecture |
| **Figure 10** | System Diagram of the System | End-to-End Sequence Diagram Across All Actors |
| **Figure 11** | Deployment Diagram | UML Runtime Host Nodes & Transport Sockets |
| **Figure 12** | Package Diagram | UML Modular Component Hierarchy |
| **Figure 13** | Class Diagram | Object-Oriented Domain Entity Model |
| **Figure 14** | Staff Authentication & Role-Based Access Gateway | Secure Login & Dynamic RBAC Portal |
| **Figure 15** | Customer Portal Mobile Home & Status Timeline | Mobile Client Dashboard & Progress Tracker |
| **Figure 16** | Intake Schedule Booking & Animal Specification Interface | Livestock Intake Form & Date Selector |
| **Figure 17** | Statutory Document & Permit Upload Interface | Camera/File Attachment & Storage Pipeline |
| **Figure 18** | Admin Intake Triage & Holding Pen Allocation Console | Barangay vs Market Queue Manager |
| **Figure 19** | Document Verification & Physical Compliance Gateway | Permit Cross-Checking & Gate Clearance Modal |
| **Figure 20** | Ante-Mortem Inspection & Corral Clinical Logbook | Live Animal Health Evaluation & Tagging |
| **Figure 21** | Slaughter Line Process Stage Tracking Board | Real-time Stunning, Bleeding, Scalding Queue |
| **Figure 22** | Post-Mortem Veterinary Examination Station | Viscera & Carcass Pathology Tagging |
| **Figure 23** | Digital Carcass Weighing Scale & MIC Approval Interface | Net Dressed Weight (kg) Entry & MIC Authorization |
| **Figure 24** | Official Digital Meat Condemnation Slip Preview | Legal Seizure Notice (CS-YYYY-XXX) & Disposal Order |
| **Figure 25** | Municipal Tariff Billing & Cashiering Workspace | Automated Fee Schedule Calculator |
| **Figure 26** | PayMongo Hosted GCash Digital Payment Gateway | Hosted Checkout Link Generation & Polling Flow |
| **Figure 27** | Official Slaughterhouse Receipt & Barcode Gate Pass | Digital Receipt (RCP-YYYY-XXX) Layout |
| **Figure 28** | Meat Releasing & Dispatch Confirmation Console | Gate Pass Validation & Release Timestamp Modal |
| **Figure 29** | Illegal Slaughter Whistleblower Reporting & Investigation Console | Anonymous Tip GPS Submission & Admin Case Triage |

---

## List of Tables

| Table | Title | Page / Section |
| :--- | :--- | :--- |
| **Table 1** | Development Tools Used | Chapter 2 |
| **Table 2** | Software Requirements (Client-side vs Admin-side) | Chapter 2 |
| **Table 3** | Recommended Hardware Requirements (Server, Desktop, Mobile, Peripherals) | Chapter 2 |
| **Table 4** | Sub-domain A: Intake Booking, Lairage Queueing, and Permit Information Requirements | Chapter 4 |
| **Table 5** | Sub-domain B: Veterinary Inspection, Carcass Weighing, and Condemnation Information Requirements | Chapter 4 |
| **Table 6** | Sub-domain C: Municipal Cashiering, PayMongo GCash, and Statutory Reports Information Requirements | Chapter 4 |
| **Table 7** | Demographic Profile of Evaluation Participants ($n = 46$) | Chapter 4 |
| **Table 8** | System Usability Scale (SUS) Item Response Analysis | Chapter 4 |
| **Table 9** | Usability vs. Learnability Subscale Breakdown | Chapter 4 |
| **Table 10**| SUS Score Distribution by Stakeholder Group | Chapter 4 |
