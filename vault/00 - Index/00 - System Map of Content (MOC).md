---
title: "Tabaco City Slaughterhouse System - Master Map of Content (MOC)"
vault_type: "System Index & Development Audit Vault"
target_system: "Tabaco City 'AA' Slaughterhouse Management Application"
created: 2026-09-26
last_updated: 2026-09-26
status: active
tags:
  - moc
  - index
  - architecture
  - audit
  - capstone
---

# Tabaco City "AA" Slaughterhouse System - Master Index (MOC)

> **Welcome to the Central Knowledge Base and System Audit Vault** for the **Tabaco City "AA" Slaughterhouse Management System**. This vault provides a comprehensive architectural index, deep-dive system audit, relational database schemas, development roadmaps, audit issue trackers, and the complete academic Capstone Manuscript draft.

---

## Visual Canvases (Obsidian Canvas)

- [[System Architecture.canvas|System Architecture Canvas]] — Interactive node map of client layers, backend, edge runtimes, and external APIs.
- [[Slaughterhouse Workflow Lifecycle.canvas|Slaughterhouse Workflow Lifecycle Canvas]] — Visual state transitions from booking intake to meat dispatch.

---

## Section 01: Architecture & System Maps

Detailed technical blueprints, state machines, and integration patterns powering the application ecosystem:

1. [[High-Level System Architecture]] — Macro architecture, multi-tier Flutter clients, Supabase BaaS, and PayMongo gateway.
2. [[End-to-End Workflow State Machine]] — Full request lifecycle (`pending` -> `approved` -> `doc_verified` -> `slaughter_started` -> `releasable` -> `paid` -> `completed`).
3. [[Flutter Mobile App Architecture]] — Citizen/Client app (`mobile_app`), auth flows, offline considerations, and state management.
4. [[Flutter Admin Panel Architecture]] — Meat inspection staff & cashier web portal (`admin_panel`), module shell, and data grids.
5. [[Supabase Backend & Edge Runtime]] — PostgreSQL tables, Realtime channels, Storage buckets, and Deno Edge Functions.
6. [[PayMongo Payment Gateway Integration]] — GCash payment link generation, webhook polling fallback, and centavo calculations.
7. [[PDF Generation & Document Lifecycle]] — Legal format slaughterhouse production reports, condemnation slips, and receipts.

---

## Section 02: System Audit & Security Analysis

Rigorous 360-degree code audit, vulnerability assessment, and risk remediation matrices:

1. [[Comprehensive System Audit Report]] — Executive audit summary, architectural health score, and risk matrix.
2. [[Security & Vulnerability Assessment]] — Critical RLS bypasses, client-side cash verification risks, and API authorization flaws.
3. [[Audit Issue Tracker]] — Prioritized index of all identified bugs, technical debt, and security vulnerabilities (P1 to P4).
4. [[State Machine Integrity & Edge Cases]] — Race conditions, orphaned inspection records, and status desynchronization risks.
5. [[Code Quality & Technical Debt Matrix]] — Duplicate fee formulas, hardcoded strings, magic numbers, and missing unit tests.
6. [[Database Security & RLS Policy Audit]] — Row-Level Security verification, anon-key capabilities, and role enforcement.

---

## Section 03: Database Schema & Data Dictionary

Comprehensive data definitions, relationships, triggers, and storage bucket layouts:

1. [[Master Entity Relationship Diagram (ERD)]] — Complete Mermaid ERD and relational key mapping.
2. [[Table - requests]] — Primary slaughter booking orders, schedule dates, animal counts, and status lifecycles.
3. [[Table - slaughter_inspection]] — Ante-mortem & post-mortem records, carcass weights, condemnation tags, and inspector signatures.
4. [[Table - payments]] — Invoices, official receipt numbers, GCash transaction references, and fee breakdowns.
5. [[Table - profiles]] — User identity, roles (`admin`, `client`, `inspector`, `cashier`), phone numbers, and addresses.
6. [[Table - notifications]] — In-app notification queue, notification types, and read/unread dispatch states.
7. [[Table - reports (Illegal Slaughter)]] — Citizen whistleblower reports, GPS geolocation, and photographic evidence.
8. [[Table - reviews]] — Customer service ratings, comments, and public feedback records.
9. [[Storage Buckets & Asset Management]] — Buckets: `avatars`, `request-documents`, `report-evidence`.

---

## Section 04: Module Reference

Granular documentation for every operational module in both applications:

### Admin Portal Modules
- [[Admin - Receiving & New Requests]] — Barangay vs. Market request triage, intake approvals, and scheduling.
- [[Admin - Document Verification]] — Veterinary health certificate, shipping permit, and brand inspection check.
- [[Admin - Slaughter & Inspection]] — Ante-mortem examination, scalding/dressing tracking, post-mortem inspection, carcass weighing, and Meat Inspection Certificate (MIC) approval.
- [[Admin - Payment & Cashiering]] — Tariff calculation (facility, corral, delivery, post-mortem per kg), cash receipting, and GCash confirmation.
- [[Admin - Meat Releasing]] — Gate pass issuance, meat release timestamps, and customer hand-off.
- [[Admin - Reports & Records]] — Daily production PDF compilation, livestock breakdowns, and revenue reporting.
- [[Admin - Illegal Slaughter Oversight]] — Investigation triage, status tracking, and enforcement response.

### Mobile Client Modules
- [[Mobile - Client Request Booking]] — Multi-step animal intake submission, document attachment, and schedule selection.
- [[Mobile - Inspection Tracking & Condemnation Slips]] — Live progress tracking, veterinary notes, and partial/total condemnation alerts.
- [[Mobile - GCash & Cash Checkout]] — Payment selection, PayMongo redirect, polling state, and receipt generation.
- [[Mobile - Illegal Slaughter Whistleblower Reporting]] — Incident submission with photo uploads, anonymous toggling, and geo-tagging.

---

## Section 05: Development & Operational Logs

Chronological records of architectural decisions, feature implementations, and sprint audits:

- [[2026-09-26 - Initial System Audit & Vault Setup]] — Full system baseline audit and documentation initialization.
- [[Feature Backlog & Remediation Plan]] — Immediate bug fixes, security hardening, and future feature implementations.

---

## Section 06: Vault Templates

Standardized templates for ongoing development logging and issue tracking:

- [[Template - Daily Dev Log]]
- [[Template - Audit Vulnerability Issue]]
- [[Template - Feature Specification]]
- [[Template - Component Reference]]

---

## Section 07: Academic Capstone Manuscript (Full Draft)

Complete formal thesis manuscript for **Polytechnic Institute of Tabaco (BSIT)**:

- [[00 - Preliminaries|Academic Preliminaries]] — Title page, Approval sheets, Panel ratings, Acknowledgement, Abstract, and Table of Contents.
- [[Chapter 1 - Introduction|Chapter 1: Introduction]] — Background, Rationale, Company Profile, Problem Statement, Objectives, Scope & Delimitation.
- [[Chapter 2 - Review of Related Literature and Technical Background|Chapter 2: Literature Review & System Design]] — Related literature, IPO Framework, RAD Model, MVC Architecture, Existing vs. Proposed Flowcharts, Use Case Analysis, Physical Deployment, Technology Stack.
- [[Chapter 3 - Methodology|Chapter 3: Methodology]] — Data sources, Data gathering techniques (Interviews, Surveys, Document Analysis), Data analysis tools (SPSS, Excel, Looker Studio), Purposive Sampling ($n = 46$).
- [[Chapter 4 - Results and Discussion|Chapter 4: Results and Discussion]] — Information requirements, System feature walkthrough with technical flowcharts, Usability evaluation (SUS Score: 85.8 / 100, Grade A+).
- [[Chapter 5 - Summary, Conclusions, and Recommendations|Chapter 5: Summary, Conclusions, and Recommendations]] — Summary of findings, Conclusions, Institutional recommendations, and Future research directions.
- [[References|References (APA 7th Edition)]] — Complete academic bibliography.
- [[Appendices|Appendices (A to G)]] — Communication letter, Technical Data Dictionary, User's Manual Guide, Information Flow DFDs, Implementation Gantt Chart, Interview Guide, and SUS Instrument.

---

## System Tag Taxonomy

- `#audit/critical` — Severe security vulnerability or financial risk requiring immediate fix.
- `#audit/high` — High severity defect or state machine flaw.
- `#audit/medium` — Code smell, performance bottleneck, or maintainability issue.
- `#capstone` — Academic thesis draft chapters and documents.
- `#module/admin` — Components within the Admin Panel.
- `#module/mobile` — Components within the Mobile App.
- `#module/supabase` — Backend database, functions, or storage policies.
- `#status/in-progress` — Currently being addressed.
- `#status/backlog` — Planned for future sprint.
