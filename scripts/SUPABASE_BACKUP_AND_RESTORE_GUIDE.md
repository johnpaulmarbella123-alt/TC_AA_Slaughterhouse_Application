# Supabase Backup, Free-Tier Safety & Restore Guide

**Target System:** Tabaco City "AA" Slaughterhouse Management System  
**Current Project Ref:** `jacgcceaxblwgdxaeaqk`  
**Cost:** **100% Free** (uses Node.js already installed on your PC — no Docker, no paid add-ons)

---

## Good News for Your December 6 Defense
- The Supabase notice says projects will only be restricted starting **December 12, 2026**, so your **December 6 defense** is safely before that date.
- Running the backup below today (and again the night before Dec 6) guarantees you have a complete copy of all database records, schema SQL, and uploaded Storage documents safely on your computer (and you can copy the folder to Google Drive or a USB flash drive).

---

## Part 1: Run a Full Local Backup Right Now (2 Steps)

1. **Copy your `service_role` key** from Supabase Dashboard:
   - Open: https://supabase.com/dashboard/project/jacgcceaxblwgdxaeaqk/settings/api
   - Under **Project API keys**, click **Reveal** next to **`service_role`** and copy it.
2. **Run in PowerShell** (inside `c:\Users\Dynabook\TCAASlaughter_App`):
   ```powershell
   $env:SUPABASE_SERVICE_ROLE_KEY="paste_your_service_role_key_here"
   node scripts/backup_supabase.mjs
   ```
   This creates `backups/supabase_backup_YYYYMMDD_HHMM/` containing:
   - `data/*.json` — Every table's rows in clean JSON
   - `restore_data.sql` — Ready-to-run SQL `INSERT` script with sequence resets
   - `all_migrations_bundle.sql` — All 39 schema/RPC/RLS migrations bundled in order
   - `storage/<bucket>/...` — All uploaded certificates, permits, avatars, and evidence photos
   - `manifest.json` — Exact row & file counts

*(Note: `backups/` is listed in `.gitignore`, so your private customer data is never pushed to GitHub.)*

---

## Part 2: Stay Under the Free Tier Quota (So It Doesn't Get Restricted on Dec 12)

1. Open **Supabase Dashboard → Organization → Usage** (click **Review usage** on the orange banner) to see which quota was exceeded (usually **Egress** or **Cached Egress** from large images/videos, or **Storage**).
2. Common free-tier fixes:
   - Delete old test rows/large test photos from **Storage** buckets that you no longer need.
   - Once usage drops below the Free Tier limit in the current billing cycle, the restriction warning clears automatically.

---

## Part 3: How to Restore to a Brand-New Free Supabase Project (~10 Minutes)

If you ever need to move to a fresh Supabase project:

1. **Create a new Free Supabase project** (under a fresh Supabase organization if needed) and note its new **Project Ref**, **Project URL**, and **`anon` key**.
2. **Restore Schema & Data**:
   - Open the new project's **SQL Editor**.
   - Run your base table setup + `all_migrations_bundle.sql` from your latest backup folder.
   - Run `restore_data.sql` to restore all records.
3. **Restore Storage Files**:
   - Create the same Storage buckets in the new project and upload the files from `backups/supabase_backup_*/storage/`.
4. **Deploy All 5 Edge Functions**:
   ```powershell
   npx supabase functions deploy send-push-notification --project-ref <NEW_REF> --no-verify-jwt
   npx supabase functions deploy send-nmic-report --project-ref <NEW_REF> --no-verify-jwt
   npx supabase functions deploy create-gcash-payment --project-ref <NEW_REF> --no-verify-jwt
   npx supabase functions deploy send-walkin-sms --project-ref <NEW_REF> --no-verify-jwt
   npx supabase functions deploy receive-walkin-sms --project-ref <NEW_REF> --no-verify-jwt
   ```
5. **Re-add Edge Function Secrets** in the new project's **Edge Functions → Secrets**:
   - `FIREBASE_SERVICE_ACCOUNT_JSON`
   - `GMAIL_USER` & `GMAIL_APP_PASSWORD`
   - `PAYMENT_GATEWAY`, `XENDIT_SECRET_KEY`, `XENDIT_PUBLIC_KEY` (or `PAYMONGO_*`)
   - `TEXTBEE_API_KEY`, `TEXTBEE_DEVICE_ID`
6. **Point Admin Panel & Mobile App to the New Project**:
   - Update `SUPABASE_URL` and `SUPABASE_ANON_KEY` in:
     - `admin_panel/.env` and `admin_panel/lib/main.dart`
     - `mobile_app/.env` and `mobile_app/lib/main.dart`
