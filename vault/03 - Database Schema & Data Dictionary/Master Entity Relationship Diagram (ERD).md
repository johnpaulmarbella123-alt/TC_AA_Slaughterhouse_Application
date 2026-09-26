---
title: "Master Entity Relationship Diagram (ERD)"
category: "Database Schema"
created: 2026-09-26
last_updated: 2026-09-26
tags:
  - database
  - erd
  - relationships
  - schema
---

# Master Entity Relationship Diagram (ERD)

The complete data model supporting the Tabaco City "AA" Slaughterhouse Application ecosystem.

---

## Relational Entity Diagram

```mermaid
erDiagram
    PROFILES ||--o{ REQUESTS : "creates"
    PROFILES ||--o{ NOTIFICATIONS : "receives"
    PROFILES ||--o{ REPORTS : "files (optional)"
    PROFILES ||--o{ REVIEWS : "submits"
    
    REQUESTS ||--|| SLAUGHTER_INSPECTION : "has"
    REQUESTS ||--o| PAYMENTS : "billed_for"
    REQUESTS ||--o{ NOTIFICATIONS : "triggers"

    PROFILES {
        uuid id PK "matches auth.users.id"
        text full_name
        text phone_number
        text address
        text role "admin, inspector, cashier, client"
        text avatar_url
        timestamp created_at
        timestamp updated_at
    }

    REQUESTS {
        bigint id PK
        uuid user_id FK "references profiles.id"
        text customer_name
        text contact_number
        text address
        text request_type "barangay, market"
        text livestock_type "hog, cattle, carabao, goat"
        int animal_count
        numeric live_weight
        date preferred_date
        text status "pending, approved, doc_verified, slaughter_started, releasable, payment_pending, paid, completed, cancelled, anti_mortem_failed, post_mortem_failed"
        text health_cert_url
        text shipping_permit_url
        text barangay_clearance_url
        timestamp created_at
        timestamp released_at
    }

    SLAUGHTER_INSPECTION {
        bigint id PK
        bigint request_id FK "references requests.id"
        text anti_mortem "Passed, Suspect, Condemned"
        text process_stage "Stunning, Bleeding, Scalding, Evisceration, Passed, Condemned"
        text post_mortem "Passed, Condemned, Retained"
        numeric carcass_weight
        text inspector_name
        text process_notes
        text condemnation_reason
        text veterinary_findings
        timestamp created_at
        timestamp updated_at
    }

    PAYMENTS {
        bigint id PK
        bigint request_id FK "references requests.id"
        numeric amount
        numeric balance
        text payment_method "Cash, GCash"
        text status "pending, paid, cancelled"
        text receipt_number "RCP-YYYY-XXX"
        text transaction_ref
        timestamp payment_date
        timestamp created_at
    }

    NOTIFICATIONS {
        bigint id PK
        uuid user_id FK "references profiles.id"
        text title
        text message
        text type "intake_approved, doc_verified, inspection_failed, payment_due, released"
        boolean is_read
        timestamp created_at
    }

    REPORTS {
        bigint id PK
        uuid user_id FK "optional whistleblower id"
        text incident_type
        text description
        text location_address
        double latitude
        double longitude
        text evidence_photo_url
        text status "Under Investigation, Resolved, Dismissed"
        timestamp created_at
    }

    REVIEWS {
        bigint id PK
        uuid user_id FK "references profiles.id"
        int rating "1 to 5"
        text comment
        timestamp created_at
    }
```

---

## Related Knowledge Links
- [[Table - requests]]
- [[Table - slaughter_inspection]]
- [[Table - payments]]
- [[Table - profiles]]
- [[Storage Buckets & Asset Management]]
