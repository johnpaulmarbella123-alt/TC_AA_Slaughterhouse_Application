---
title: "Table - reviews"
category: "Database Schema"
created: 2026-09-26
last_updated: 2026-09-26
tags:
  - database
  - schema
  - reviews
  - feedback
---

 ⭐ Table: `reviews`

Stores citizen feedback, abattoir service ratings, and qualitative comments to monitor public service satisfaction.

---

## Schema Definition

| Column Name | Data Type | Nullable | Description |
| :--- | :--- | :---: | :--- |
| `id` | `BIGINT` | NO | Primary key identifier |
| `user_id` | `UUID` | NO | Foreign key referencing `profiles.id` |
| `rating` | `INTEGER` | NO | Numerical star rating from 1 to 5 |
| `comment` | `TEXT` | YES | Written user feedback |
| `created_at` | `TIMESTAMPTZ` | NO | Submission timestamp |

---

## Related Knowledge Links
- [[Table - profiles]]
- [[Flutter Mobile App Architecture]]
