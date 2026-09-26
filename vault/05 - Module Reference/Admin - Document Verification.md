---
title: "Admin - Document Verification"
category: "Module Reference"
created: 2026-09-26
last_updated: 2026-09-26
tags:
  - module
  - admin
  - verification
  - compliance
---

# Admin Module: Document Verification

**Source File**: `admin_panel/lib/screens/document_verification_page.dart`  
**Target Roles**: Licensing Officers, Veterinary Inspection Clerks.

---

## Purpose & Functionality
Mandated by statutory veterinary transport laws, this module verifies physical compliance documents before livestock can enter the abattoir holding pens:
1. **Veterinary Health Certificate (VHC)** issued by a licensed government or private veterinarian.
2. **Livestock Shipping Permit (SP)** from the Bureau of Animal Industry (BAI).
3. **Certificate of Ownership & Transfer / Barangay Clearance**.

---

## Key Operations & Workflows
- **Pass Verification**: Transitions request to `doc_verified` status and creates initial empty `slaughter_inspection` record.
- **Reject / Invalidate**: Marks request as `cancelled` with an explanation message (e.g. *Expired Shipping Permit*, *Mismatched Ear Tag/Brand*).

---

## Related Knowledge Links
- [[Table - requests]]
- [[Admin - Slaughter & Inspection]]
- [[Storage Buckets & Asset Management]]
