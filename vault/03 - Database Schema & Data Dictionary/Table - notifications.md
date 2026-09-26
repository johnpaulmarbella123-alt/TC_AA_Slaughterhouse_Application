---
title: "Table - notifications"
category: "Database Schema"
created: 2026-09-26
last_updated: 2026-09-26
tags:
  - database
  - schema
  - notifications
  - realtime
---

# Table: `notifications`

Stores asynchronous alerts and status update notifications pushed to clients and administrators.

---

## Schema Definition

| Column Name | Data Type | Nullable | Description |
| :--- | :--- | :---: | :--- |
| `id` | `BIGINT` | NO | Primary key identifier |
| `user_id` | `UUID` | NO | Foreign key referencing `profiles.id` (Target recipient) |
| `title` | `TEXT` | NO | Short header (e.g. *Request Approved*, *Documents Verified*) |
| `message` | `TEXT` | NO | Explanatory message content |
| `type` | `TEXT` | YES | Event category: `'intake_approved'`, `'doc_verified'`, `'doc_rejected'`, `'inspection_failed'`, `'ready_for_payment'`, `'paid'`, `'meat_released'` |
| `is_read` | `BOOLEAN` | NO | Read/Unread flag (`false` by default) |
| `created_at` | `TIMESTAMPTZ` | NO | Alert dispatch timestamp |

---

## Related Knowledge Links
- [[Table - profiles]]
- [[Flutter Mobile App Architecture]]
