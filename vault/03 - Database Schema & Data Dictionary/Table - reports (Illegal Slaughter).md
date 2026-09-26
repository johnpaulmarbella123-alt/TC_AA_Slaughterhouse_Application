---
title: "Table - reports (Illegal Slaughter)"
category: "Database Schema"
created: 2026-09-26
last_updated: 2026-09-26
tags:
  - database
  - schema
  - illegal-slaughter
  - enforcement
---

# Table: `reports` (Illegal Slaughter Whistleblower)

Stores anonymous or registered citizen whistleblower reports on illegal, clandestine, or "botcha" slaughtering operations within Tabaco City.

---

## Schema Definition

| Column Name | Data Type | Nullable | Description |
| :--- | :--- | :---: | :--- |
| `id` | `BIGINT` | NO | Primary key identifier |
| `user_id` | `UUID` | YES | Optional whistleblower identity (Null if reported anonymously) |
| `incident_type` | `TEXT` | NO | Violation type: `'Illegal Slaughter'`, `'Uninspected Meat Distribution'`, `'Cruelty / Sanitary Violation'` |
| `description` | `TEXT` | NO | Narrative details of incident and suspected perpetrators |
| `location_address` | `TEXT` | NO | Street address, landmark, or barangay |
| `latitude` | `DOUBLE PRECISION`| YES | GPS latitude coordinate |
| `longitude` | `DOUBLE PRECISION`| YES | GPS longitude coordinate |
| `evidence_photo_url`| `TEXT` | YES | URL to photo evidence stored in `report-evidence` bucket |
| `status` | `TEXT` | NO | Case state: `'Mobile Submissions'`, `'Under Investigation'`, `'Resolved'`, `'Dismissed'` |
| `investigator_notes`| `TEXT` | YES | Veterinary enforcement team findings and actions taken |
| `created_at` | `TIMESTAMPTZ` | NO | Report filing timestamp |

---

## Related Knowledge Links
- [[Admin - Illegal Slaughter Oversight]]
- [[Mobile - Illegal Slaughter Whistleblower Reporting]]
- [[Storage Buckets & Asset Management]]
