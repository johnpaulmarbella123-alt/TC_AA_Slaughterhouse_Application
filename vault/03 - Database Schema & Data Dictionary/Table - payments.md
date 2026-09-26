---
title: "Table - payments"
category: "Database Schema"
created: 2026-09-26
last_updated: 2026-09-26
tags:
  - database
  - schema
  - payments
  - cashiering
---

# Table: `payments`

Stores financial invoices, fee breakdowns, payment receipts, payment methods (Cash/GCash), and clearing statuses.

---

## Schema Definition

| Column Name | Data Type | Nullable | Description |
| :--- | :--- | :---: | :--- |
| `id` | `BIGINT` | NO | Primary key identifier |
| `request_id` | `BIGINT` | NO | Foreign key referencing `requests.id` |
| `amount` | `NUMERIC(10,2)`| NO | Total assessed fee (₱ PHP) |
| `balance` | `NUMERIC(10,2)`| NO | Remaining balance due (₱0.00 when paid) |
| `payment_method` | `TEXT` | YES | Method used: `'Cash'`, `'GCash'` |
| `status` | `TEXT` | NO | Payment state: `'pending'`, `'paid'`, `'cancelled'` |
| `receipt_number` | `TEXT` | YES | Official Slaughterhouse Receipt (`RCP-YYYY-XXX`) |
| `transaction_ref`| `TEXT` | YES | PayMongo Link ID or GCash transaction reference number |
| `payment_date` | `TIMESTAMPTZ` | YES | Timestamp of payment confirmation |
| `created_at` | `TIMESTAMPTZ` | NO | Invoice calculation timestamp |

---

## Related Knowledge Links
- [[PayMongo Payment Gateway Integration]]
- [[Admin - Payment & Cashiering]]
- [[Mobile - GCash & Cash Checkout]]
