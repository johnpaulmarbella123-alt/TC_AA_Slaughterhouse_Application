---
title: "State Machine Integrity & Edge Cases"
category: "Audit"
created: 2026-09-26
last_updated: 2026-09-26
tags:
  - state-machine
  - edge-cases
  - race-conditions
  - integrity
---

# State Machine Integrity & Edge Cases

An audit of the state transitions reveals potential failure modes, race conditions, and orphaned states across the request lifecycle.

---

## Identified Edge Cases & Race Conditions

 1. The "Ghost Inspection" Edge Case (Desynchronized Tables)
- **Mechanism**: The Admin panel updates `requests.status` to `releasable` after updating `slaughter_inspection.carcass_weight`.
- **Failure Scenario**: If an inspector submits the dialog while experiencing momentary network packet loss, the `slaughter_inspection` update might succeed while the `requests` table update fails.
- **Result**: The request remains listed as `slaughter_started` in the intake queue, but holds a complete carcass weight and inspection record in the background.
- **Remediation**: Use a PostgreSQL stored procedure or RPC function (`complete_inspection(p_request_id, p_weight, p_inspector)`) to wrap both updates in an ACID transaction:
  ```sql
  CREATE OR REPLACE FUNCTION complete_inspection(
    p_request_id BIGINT,
    p_carcass_weight NUMERIC,
    p_inspector_name TEXT,
    p_post_mortem TEXT
  ) RETURNS VOID AS $$
  BEGIN
    UPDATE slaughter_inspection
    SET carcass_weight = p_carcass_weight,
        inspector_name = p_inspector_name,
        post_mortem = p_post_mortem,
        process_stage = 'Passed'
    WHERE request_id = p_request_id;

    UPDATE requests
    SET status = 'releasable'
    WHERE id = p_request_id;
  END;
  $$ LANGUAGE plpgsql;
  ```

---

 2. The "Double Payment" Collision
- **Mechanism**: A customer opens the GCash payment link in the browser, while simultaneously their agent arrives in person at the cashier counter and pays in cash.
- **Failure Scenario**: Both the online webhook and the cashier cashiering modal attempt to mark the invoice as paid.
- **Remediation**: Ensure `payments` table uses optimistic concurrency locking or state checks (`WHERE status = 'unpaid'` or `WHERE status = 'payment_pending'`).

---

 3. Partial vs Total Condemnation Handling
- **Mechanism**: In `slaughter_inspection_page.dart`, an animal can have specific condemned organs (e.g. Liver, Lungs) while the remaining carcass is passed fit for human consumption.
- **Integrity Requirement**: Carcass weight recorded for fee computation must be the **net edible weight** (Live weight minus condemned portions) to avoid overcharging clients.

---

## Related Knowledge Links
- [[End-to-End Workflow State Machine]]
- [[Table - slaughter_inspection]]
- [[Audit Issue Tracker]]
