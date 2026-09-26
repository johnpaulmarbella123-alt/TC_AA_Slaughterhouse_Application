---
title: "Storage Buckets & Asset Management"
category: "Database Schema"
created: 2026-09-26
last_updated: 2026-09-26
tags:
  - storage
  - buckets
  - uploads
  - assets
---

# Storage Buckets & Asset Management

Overview of Supabase Object Storage buckets, security policies, upload lifecycles, and file conventions.

---

## Storage Buckets Configuration

 1. `request-documents`
- **Purpose**: Holds statutory livestock travel documents uploaded during mobile booking.
- **Accepted MIME Types**: `image/jpeg`, `image/png`, `application/pdf`.
- **Naming Pattern**: `{user_id}/{timestamp}_{doc_type}.jpg`
- **Access Rule**: Public Read (for inspector review), Authenticated Write.

 2. `report-evidence`
- **Purpose**: Holds photographic evidence submitted with illegal slaughter reports.
- **Accepted MIME Types**: `image/jpeg`, `image/png`.
- **Naming Pattern**: `evidence/{timestamp}_{random_uuid}.jpg`
- **Access Rule**: Public Read, Authenticated/Anon Write.

 3. `avatars`
- **Purpose**: Stores user profile photos.
- **Accepted MIME Types**: `image/jpeg`, `image/png`.
- **Naming Pattern**: `{user_id}/{timestamp}_avatar.jpg`
- **Access Rule**: Public Read, Authenticated Write (Owner only).

---

## Related Knowledge Links
- [[Supabase Backend & Edge Runtime]]
- [[Database Security & RLS Policy Audit]]
