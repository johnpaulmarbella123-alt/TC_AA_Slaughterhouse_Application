---
title: "Feature Backlog & Remediation Plan"
category: "Development Log"
created: 2026-09-26
last_updated: 2026-09-26
tags:
  - backlog
  - roadmap
  - remediation
  - tasks
---

# Feature Backlog & Remediation Plan

A structured development roadmap prioritizing critical security hardening, code refactoring, and new feature capabilities.

---

## Sprint 1: Security Hotfixes & Payment Integrity (Current)
- [ ] **HOTFIX-01**: Change mobile Cash on Pickup action to set `status = 'payment_pending'` in `requests` and `status = 'pending'` in `payments`.
- [ ] **HOTFIX-02**: Add Cashier verification action button in `admin_panel/lib/screens/payment_cashiering_page.dart` to mark cash as paid upon cash intake.
- [ ] **HOTFIX-03**: Enforce PostgreSQL RLS policies to prevent non-admin/cashier roles from updating `payments.status`.

---

## Sprint 2: Webhooks & Transaction Atomicity
- [ ] **FEAT-01**: Implement `supabase/functions/paymongo-webhook` Edge Function to listen to `payment.paid` events and update DB atomically with service role.
- [ ] **FEAT-02**: Implement PostgreSQL stored procedure `complete_inspection()` to update `slaughter_inspection` and `requests.status` atomically.
- [ ] **FEAT-03**: Centralize fee computation into a shared configuration or database table.

---

## Sprint 3: Reporting & Operational Enhancements
- [ ] **FEAT-04**: Add custom date range picker in `ReportsRecordsPage` (Admin Panel).
- [ ] **FEAT-05**: Implement offline queue for Meat Inspectors recording carcass weights in low-signal abattoir zones.
- [ ] **FEAT-06**: Image compression prior to uploading photos in whistleblower reports.

---

## Related Knowledge Links
- [[Audit Issue Tracker]]
- [[2026-09-26 - Initial System Audit & Vault Setup]]
- [[Comprehensive System Audit Report]]
