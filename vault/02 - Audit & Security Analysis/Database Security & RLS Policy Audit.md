---
title: "Database Security & RLS Policy Audit"
category: "Audit"
created: 2026-09-26
last_updated: 2026-09-26
tags:
  - database
  - security
  - rls
  - postgresql
  - permissions
---

# Database Security & RLS Policy Audit

This document outlines the required PostgreSQL Row-Level Security (RLS) policies and security postures for every table in the database to prevent privilege escalation and unauthorized data manipulation.

---

## Required RLS Policy Definitions

 1. `requests` Table
```sql
ALTER TABLE requests ENABLE ROW LEVEL SECURITY;

-- Clients can only see their own requests; Staff can see all
CREATE POLICY "Users can view own requests or staff can view all"
ON requests FOR SELECT
USING (
  auth.uid() = user_id OR 
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin', 'inspector', 'cashier'))
);

-- Clients can insert requests under their own user_id
CREATE POLICY "Users can create requests"
ON requests FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Only Staff can update request statuses (Clients cannot approve/complete their own)
CREATE POLICY "Only staff can update requests"
ON requests FOR UPDATE
USING (
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin', 'inspector', 'cashier'))
);
```

---

 2. `payments` Table
```sql
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;

-- Clients can only view payments related to their requests
CREATE POLICY "Users view own payments"
ON payments FOR SELECT
USING (
  EXISTS (SELECT 1 FROM requests WHERE requests.id = payments.request_id AND requests.user_id = auth.uid()) OR
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin', 'cashier'))
);

-- Only Cashiers and Admins can update payment records
CREATE POLICY "Cashier and Admin update payments"
ON payments FOR UPDATE
USING (
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin', 'cashier'))
);
```

---

 3. `slaughter_inspection` Table
```sql
ALTER TABLE slaughter_inspection ENABLE ROW LEVEL SECURITY;

-- Read access for owners and staff
CREATE POLICY "Inspection read access"
ON slaughter_inspection FOR SELECT
USING (
  EXISTS (SELECT 1 FROM requests WHERE requests.id = slaughter_inspection.request_id AND requests.user_id = auth.uid()) OR
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin', 'inspector'))
);

-- Write/Update restricted strictly to Inspectors and Admins
CREATE POLICY "Inspector write access"
ON slaughter_inspection FOR ALL
USING (
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin', 'inspector'))
);
```

---

## Related Knowledge Links
- [[Security & Vulnerability Assessment]]
- [[Master Entity Relationship Diagram (ERD)]]
- [[Supabase Backend & Edge Runtime]]
