---
title: "End-to-End Workflow State Machine"
category: "Architecture"
created: 2026-09-26
last_updated: 2026-09-26
tags:
  - workflow
  - state-machine
  - lifecycle
  - inspection
---

# End-to-End Workflow State Machine

The core business logic of the Tabaco City Slaughterhouse is modeled around an orchestrated statutory workflow governed by National Meat Inspection Service (NMIS) standards. Every livestock batch transitions through distinct states across administrative, veterinary, financial, and logistics checkpoints.

---

 Comprehensive State Machine Diagram

```mermaid
stateDiagram-v2
    [*] --> Pending: Citizen submits request via Mobile

    state "Pending (Intake)" as Pending {
        note right of Pending: Request registered in requests table.\nRequest Type: Barangay or Market.
    }

    Pending --> Approved: Admin approves intake schedule
    Pending --> Rejected: Admin rejects intake (Capacity / Incomplete)

    state "Approved (Intake Verified)" as Approved {
        note right of Approved: Animals scheduled for physical arrival.
    }

    Approved --> DocVerified: Admin verifies physical documents (Health cert, Shipping permit)
    Approved --> Cancelled: Document check fails / Animal rejected

    state "Doc Verified" as DocVerified {
        note right of DocVerified: Livestock admitted to holding corral.\nAnte-Mortem exam initiated.
    }

    DocVerified --> AntiMortemFailed: Ante-mortem disease / unfit detected
    DocVerified --> SlaughterStarted: Ante-mortem passed, slaughter begins

    state "Anti Mortem Failed (Condemned)" as AntiMortemFailed {
        note right of AntiMortemFailed: Total condemnation slip issued.\nIncinerated / Disposed.
    }

    state "Slaughter Started (Processing)" as SlaughterStarted {
        note right of SlaughterStarted: Stunning, Bleeding, Scalding, Evisceration.\nPost-Mortem Inspection.
    }

    SlaughterStarted --> PostMortemFailed: Pathological lesions / Total condemnation
    SlaughterStarted --> Releasable: Post-mortem passed, Carcass weighed, MIC generated

    state "Post Mortem Failed (Condemned)" as PostMortemFailed {
        note right of PostMortemFailed: Condemnation slip generated.\nCarcass confiscated.
    }

    state "Releasable (Awaiting Payment)" as Releasable {
        note right of Releasable: Fees calculated in payments table.\nCarcass stored in cold room/hanging.
    }

    Releasable --> PaymentPending: Customer selects Cash on Pickup
    Releasable --> Paid: Customer pays via GCash (PayMongo) or Cashier confirms Cash

    state "Paid (Payment Cleared)" as Paid {
        note right of Paid: Official Receipt (RCP-YYYY-XXX) generated.\nGate pass ready.
    }

    Paid --> Completed: Meat released to dealer / transporter

    state "Completed (Dispatched)" as Completed {
        note right of Completed: Meat dispatch recorded (released_at set).\nArchived to Daily Reports.
    }

    Completed --> [*]
    Rejected --> [*]
    Cancelled --> [*]
    AntiMortemFailed --> [*]
    PostMortemFailed --> [*]
```

---

## State Definitions & Data Invariants

| Status Key (`requests.status`) | Actor Responsible | Trigger Condition | Database Mutations | Notifications Dispatched |
| :--- | :--- | :--- | :--- | :--- |
| `pending` | Citizen (`mobile_app`) | Submits booking form | Inserts row into `requests` | "Request Submitted" |
| `approved` | Intake Admin (`admin_panel`) | Clicks "Approve" in Receiving tab | `requests.status = 'approved'` | "Request Approved" with preferred date |
| `doc_verified` | Inspector (`admin_panel`) | Approves permits in Document Verification | `requests.status = 'doc_verified'` | "Documents Verified" |
| `anti_mortem_failed` | Inspector (`admin_panel`) | Flags animal disease during Ante-Mortem | `requests.status = 'anti_mortem_failed'`, `slaughter_inspection.anti_mortem = 'Failed'` | "Ante-Mortem Inspection Failed" |
| `slaughter_started` | Inspector / Staff (`admin_panel`) | Process tagging moved to Bleeding/Dressing | `requests.status = 'slaughter_started'`, `slaughter_inspection.process_stage = 'Slaughtering'` | "Slaughter In Progress" |
| `post_mortem_failed` | Inspector (`admin_panel`) | Complete carcass condemnation | `requests.status = 'post_mortem_failed'`, `slaughter_inspection.post_mortem = 'Condemned'` | "Post-Mortem Inspection Condemned" |
| `releasable` | Inspector (`admin_panel`) | Post-Mortem passed, enters carcass weight | `requests.status = 'releasable'`, `slaughter_inspection.carcass_weight = W`, `payments` record created | "Inspection Completed - Ready for Payment" |
| `payment_pending` | Citizen (`mobile_app`) | Citizen selects "Cash on Pickup" | `payments.payment_method = 'Cash'`, `payments.status = 'pending'` | "Payment Pending" |
| `paid` | Cashier (`admin_panel`) or GCash Engine | Online payment verified or Cash received | `payments.status = 'paid'`, `payments.balance = 0`, `requests.status = 'paid'` | "Payment Received - Ready for Pickup" |
| `completed` | Release Officer (`admin_panel`) | Confirms pickup / vehicle loading | `requests.status = 'completed'`, `requests.released_at = NOW()` | "Meat Released" |
| `cancelled` | Admin or Citizen | Rejection or user withdrawal | `requests.status = 'cancelled'` | "Request Cancelled" |

---

## Critical Workflow Vulnerabilities Identified

1. **Premature `paid` Status Mutation on Mobile**:
   - In `mobile_app/lib/screen/select_payment_screen.dart`, when a user taps "Cash on Pickup", the client application directly executes:
     ```dart
     await supabase.from('payments').update({'status': 'paid', 'balance': 0}).eq('request_id', reqId);
     await supabase.from('requests').update({'status': 'paid'}).eq('id', reqId);
     ```
   - **Vulnerability Impact**: The mobile client marks the bill as fully paid before any physical cash is received by the cashier.
   - **Remediation**: Transition to status `payment_pending` and let the Admin Cashier mutate status to `paid` upon physical exchange. See [[Security & Vulnerability Assessment]].

2. **Parallel Process Stage Desynchronization**:
   - The system maintains status in two separate places: `requests.status` and `slaughter_inspection.process_stage`.
   - Without an atomic database transaction or trigger, failure in updating one creates orphaned or mismatched records (e.g. `requests.status == 'releasable'` while `slaughter_inspection.process_stage == 'Scalding'`). See [[State Machine Integrity & Edge Cases]].

---

## Related Knowledge Links
- [[Table - requests]]
- [[Table - slaughter_inspection]]
- [[Table - payments]]
- [[Security & Vulnerability Assessment]]
- [[State Machine Integrity & Edge Cases]]
