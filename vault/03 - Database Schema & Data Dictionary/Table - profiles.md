---
title: "Table - profiles"
category: "Database Schema"
created: 2026-09-26
last_updated: 2026-09-26
tags:
  - database
  - schema
  - profiles
  - auth
---

# Table: `profiles`

Stores user profile metadata and role-based access control assignments, linked 1-to-1 with Supabase Auth identities (`auth.users.id`).

---

## Schema Definition

| Column Name | Data Type | Nullable | Description |
| :--- | :--- | :---: | :--- |
| `id` | `UUID` | NO | Primary key matching `auth.users.id` |
| `full_name` | `TEXT` | YES | Full legal name of user/officer |
| `phone_number` | `TEXT` | YES | Primary contact number |
| `address` | `TEXT` | YES | Physical address / barangay |
| `role` | `TEXT` | NO | User role: `'client'`, `'admin'`, `'inspector'`, `'cashier'` |
| `avatar_url` | `TEXT` | YES | Supabase storage link to profile avatar |
| `created_at` | `TIMESTAMPTZ` | NO | Account creation timestamp |
| `updated_at` | `TIMESTAMPTZ` | YES | Last profile modification timestamp |

---

## Related Knowledge Links
- [[Supabase Backend & Edge Runtime]]
- [[Database Security & RLS Policy Audit]]
