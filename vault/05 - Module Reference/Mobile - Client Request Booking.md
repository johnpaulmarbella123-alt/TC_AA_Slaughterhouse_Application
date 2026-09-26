---
title: "Mobile - Client Request Booking"
category: "Module Reference"
created: 2026-09-26
last_updated: 2026-09-26
tags:
  - module
  - mobile
  - booking
  - intake
---

# Mobile Module: Client Request Booking

**Source File**: `mobile_app/lib/screen/requests.dart`  
**Target Roles**: Meat Dealers, Hog Raisers, Farmers, Public Citizens.

---

## Purpose & Functionality
Allows registered citizens to submit slaughter reservations with complete statutory documentation, avoiding long queues at the slaughterhouse intake counter.

---

## Intake Booking Fields
1. **Customer & Origin Details**: Name, contact phone, farm address.
2. **Livestock Specification**: Species (`hog`, `cattle`, `carabao`, `goat`), head count, estimated live weight.
3. **Distribution Channel**:
   - `Barangay`: For local neighborhood consumption.
   - `Market`: For commercial distribution at Tabaco Public Market.
4. **Document Attachments**:
   - Camera/File picker uploads for Veterinary Health Certificate, Shipping Permit, and Barangay Clearance saved to `request-documents` bucket.
5. **Preferred Slaughter Date**: Date picker selection.

---

## Related Knowledge Links
- [[Table - requests]]
- [[Admin - Receiving & New Requests]]
- [[Flutter Mobile App Architecture]]
