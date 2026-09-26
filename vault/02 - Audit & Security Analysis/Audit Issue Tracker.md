---
title: "Audit Issue Tracker"
category: "Audit"
created: 2026-09-26
last_updated: 2026-09-26
tags:
  - audit
  - tracker
  - issues
  - backlog
---

# Audit Issue Tracker

A prioritized, actionable matrix of all identified bugs, architectural defects, security issues, and technical debt across the Tabaco City Slaughterhouse application ecosystem.

---

## Priority Legend
- `P1 - CRITICAL`: Blocker, immediate security risk, financial loss vulnerability, or system crash.
- `P2 - HIGH`: Major workflow inconsistency, broken state synchronization, or unhandled failure mode.
- `P3 - MEDIUM`: Technical debt, code duplication, missing error handling, or sub-optimal UX.
- `P4 - LOW`: UI alignment, polish, minor refactor, or nice-to-have documentation.

---

## Master Issue Matrix

| Issue Key | Priority | Module | Summary | Status | Assignee |
| :--- | :---: | :--- | :--- | :---: | :---: |
| **ISSUE-01** | `P1` | `Mobile / Payments` | Cash on pickup directly sets `paid` and `balance = 0` on client | `OPEN` | Dev Team |
| **ISSUE-02** | `P1` | `Supabase / Edge` | Missing server-to-server PayMongo webhook event handler | `OPEN` | Backend Dev |
| **ISSUE-03** | `P2` | `Database / RLS` | Restrict `payments` and `requests` update permissions to Admin/Staff roles | `OPEN` | DBA / Supabase |
| **ISSUE-04** | `P2` | `Admin / Inspection` | Non-atomic update between `requests.status` and `slaughter_inspection` | `OPEN` | Fullstack Dev |
| **ISSUE-05** | `P2` | `Admin & Mobile` | Hardcoded duplicated fee calculation constants across apps | `OPEN` | Flutter Dev |
| **ISSUE-06** | `P3` | `Mobile / Network` | URL hacking via string replacement `supabase.rest.url.replaceAll()` | `OPEN` | Mobile Dev |
| **ISSUE-07** | `P3` | `Admin / Reports` | PDF Generator hardcodes animal types via string regex heuristics | `OPEN` | Admin Dev |
| **ISSUE-08** | `P3` | `Mobile / Uploads` | Missing file size compression and MIME type validation on uploads | `OPEN` | Mobile Dev |
| **ISSUE-09** | `P3` | `Admin / UI` | Table overflow when rendering on narrow desktop/tablet screens | `OPEN` | UI/UX Dev |
| **ISSUE-10** | `P4` | `Mobile / Auth` | Password strength validation missing on mobile registration | `OPEN` | Mobile Dev |
| **ISSUE-11** | `P4` | `Admin / PDF` | Custom date range filtering in Reports & Records export | `OPEN` | Fullstack Dev |

---

## Detailed Issue Breakdown

 [ISSUE-01] Cash On Pickup Direct Confirmation
- **Affected File**: `mobile_app/lib/screen/select_payment_screen.dart`
- **Resolution**: Change update mutation to `status: 'payment_pending'` in `requests` and `status: 'pending'` in `payments`.
- **Target Release**: v1.0.1 Hotfix

 [ISSUE-02] PayMongo Webhook Consumer
- **Affected File**: `supabase/functions/create-gcash-payment`
- **Resolution**: Deploy `paymongo-webhook` Edge Function to listen to `payment.paid` events and verify signatures.
- **Target Release**: v1.1.0

 [ISSUE-05] Centralized Fee Engine
- **Affected Files**: `admin_panel/lib/screens/payment_cashiering_page.dart` & `mobile_app/lib/screen/payment.dart`
- **Resolution**: Create a dedicated `fees` table in Supabase or a shared calculation utility to prevent tariff drift.
- **Target Release**: v1.1.0

---

## Related Knowledge Links
- [[Security & Vulnerability Assessment]]
- [[State Machine Integrity & Edge Cases]]
- [[Feature Backlog & Remediation Plan]]
