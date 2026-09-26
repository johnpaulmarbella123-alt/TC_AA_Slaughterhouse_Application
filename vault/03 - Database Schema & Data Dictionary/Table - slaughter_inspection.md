---
title: "Table - slaughter_inspection"
category: "Database Schema"
created: 2026-09-26
last_updated: 2026-09-26
tags:
  - database
  - schema
  - inspection
  - veterinary
---

# Table: `slaughter_inspection`

Records veterinary parameters, process stages, ante-mortem and post-mortem findings, carcass weights, and condemnation certificates.

---

## Schema Definition

| Column Name | Data Type | Nullable | Description |
| :--- | :--- | :---: | :--- |
| `id` | `BIGINT` | NO | Primary key identifier |
| `request_id` | `BIGINT` | NO | Foreign key referencing `requests.id` (Unique 1-to-1) |
| `anti_mortem` | `TEXT` | YES | Ante-mortem status: `'Passed'`, `'Suspect'`, `'Failed'` |
| `process_stage` | `TEXT` | YES | Process step: `'Stunning'`, `'Bleeding'`, `'Scalding'`, `'Evisceration'`, `'Passed'`, `'Condemned'` |
| `post_mortem` | `TEXT` | YES | Post-mortem status: `'Passed'`, `'Condemned'`, `'Retained'` |
| `carcass_weight` | `NUMERIC(8,2)`| YES | Net dressed carcass weight in kilograms (Used for post-mortem fee) |
| `inspector_name` | `TEXT` | YES | Name and license number of certifying Meat Inspector |
| `process_notes` | `TEXT` | YES | General veterinary observations and handling remarks |
| `condemnation_reason` | `TEXT` | YES | Pathological diagnosis if condemned (e.g. *Septicemia*, *Fascioliasis*) |
| `veterinary_findings` | `TEXT` | YES | Detailed clinical findings for condemnation certificates |
| `created_at` | `TIMESTAMPTZ` | NO | Initial inspection initiation timestamp |
| `updated_at` | `TIMESTAMPTZ` | YES | Last inspection status update timestamp |

---

## Related Knowledge Links
- [[Table - requests]]
- [[Admin - Slaughter & Inspection]]
- [[Mobile - Inspection Tracking & Condemnation Slips]]
