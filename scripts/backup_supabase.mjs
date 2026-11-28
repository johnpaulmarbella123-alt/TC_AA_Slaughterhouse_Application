#!/usr/bin/env node
/**
 * Zero-Dependency Full Supabase Backup Script
 * Target: Tabaco City "AA" Slaughterhouse Management System
 *
 * Exports:
 *  1. All public tables -> backups/<timestamp>/data/<table>.json
 *  2. Idempotent SQL restore file -> backups/<timestamp>/restore_data.sql
 *  3. Consolidated schema migrations -> backups/<timestamp>/all_migrations_bundle.sql
 *  4. All Storage bucket files -> backups/<timestamp>/storage/<bucket>/...
 *  5. Summary report -> backups/<timestamp>/manifest.json
 *
 * Usage (PowerShell):
 *   $env:SUPABASE_SERVICE_ROLE_KEY="eyJ..."
 *   node scripts/backup_supabase.mjs
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ROOT_DIR = path.resolve(__dirname, "..");

// Optional local env file: scripts/.backup.env (gitignored)
function loadLocalEnv() {
  const envPath = path.join(__dirname, ".backup.env");
  if (!fs.existsSync(envPath)) return;
  const lines = fs.readFileSync(envPath, "utf8").split(/\r?\n/);
  for (const raw of lines) {
    const line = raw.trim();
    if (!line || line.startsWith("#")) continue;
    const eqIdx = line.indexOf("=");
    if (eqIdx === -1) continue;
    const key = line.slice(0, eqIdx).trim();
    let val = line.slice(eqIdx + 1).trim();
    if (
      (val.startsWith('"') && val.endsWith('"')) ||
      (val.startsWith("'") && val.endsWith("'"))
    ) {
      val = val.slice(1, -1);
    }
    if (!process.env[key]) process.env[key] = val;
  }
}

loadLocalEnv();

const SUPABASE_URL = (
  process.env.SUPABASE_URL || "https://jacgcceaxblwgdxaeaqk.supabase.co"
).replace(/\/+$/, "");
const SERVICE_ROLE_KEY = (process.env.SUPABASE_SERVICE_ROLE_KEY || "").trim();

if (!SERVICE_ROLE_KEY) {
  console.error(
    "\n❌ Missing SUPABASE_SERVICE_ROLE_KEY.\n" +
      "Get it from: https://supabase.com/dashboard/project/jacgcceaxblwgdxaeaqk/settings/api\n" +
      "(Under Project API keys -> service_role -> Reveal & Copy)\n\n" +
      "Then run in PowerShell:\n" +
      '  $env:SUPABASE_SERVICE_ROLE_KEY="your_service_role_key_here"\n' +
      "  node scripts/backup_supabase.mjs\n"
  );
  process.exit(1);
}

const HEADERS = {
  apikey: SERVICE_ROLE_KEY,
  Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
};

// Preferred foreign-key restore order
const PRIORITY_TABLES = [
  "system_settings",
  "profiles",
  "regular_dealers",
  "requests",
  "slaughter_inspection",
  "payments",
  "notifications",
  "staff_notifications",
  "reviews",
  "illegal_slaughter_reports",
  "dealer_role_change_requests",
  "deleted_customer_accounts",
  "nmic_transmissions",
  "walkin_sms_replies",
  "user_push_tokens",
  "audit_logs",
  "reports",
];

function timestampTag() {
  const now = new Date();
  const pad = (n) => String(n).padStart(2, "0");
  return (
    `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}_` +
    `${pad(now.getHours())}${pad(now.getMinutes())}`
  );
}

function sqlLiteral(value) {
  if (value === null || value === undefined) return "NULL";
  if (typeof value === "boolean") return value ? "TRUE" : "FALSE";
  if (typeof value === "number") return Number.isFinite(value) ? String(value) : "NULL";
  if (typeof value === "object") {
    const jsonStr = JSON.stringify(value).replace(/'/g, "''");
    return `'${jsonStr}'::jsonb`;
  }
  return `'${String(value).replace(/'/g, "''")}'`;
}

async function discoverPublicTables() {
  const discovered = new Set(PRIORITY_TABLES);
  try {
    const res = await fetch(`${SUPABASE_URL}/rest/v1/`, { headers: HEADERS });
    if (res.ok) {
      const spec = await res.json();
      const paths = spec?.paths || {};
      for (const p of Object.keys(paths)) {
        if (!p.startsWith("/") || p.startsWith("/rpc/") || p === "/") continue;
        const tableName = p.slice(1).trim();
        if (tableName && /^[a-zA-Z0-9_]+$/.test(tableName)) {
          discovered.add(tableName);
        }
      }
    }
  } catch (err) {
    console.warn("⚠ Could not auto-discover OpenAPI tables, using known list:", err.message);
  }

  // Keep priority tables first, then any extra discovered tables alphabetically
  const extras = [...discovered].filter((t) => !PRIORITY_TABLES.includes(t)).sort();
  return [...PRIORITY_TABLES, ...extras];
}

async function fetchAllRows(table) {
  const rows = [];
  const pageSize = 1000;
  let offset = 0;

  while (true) {
    const res = await fetch(`${SUPABASE_URL}/rest/v1/${table}?select=*`, {
      headers: {
        ...HEADERS,
        Range: `${offset}-${offset + pageSize - 1}`,
        Prefer: "count=exact",
      },
    });

    if (res.status === 404 || res.status === 400) {
      return { exists: false, rows: [], status: res.status };
    }
    if (!res.ok) {
      const errText = await res.text();
      return { exists: false, rows: [], status: res.status, error: errText };
    }

    const batch = await res.json();
    if (!Array.isArray(batch)) break;
    rows.push(...batch);
    if (batch.length < pageSize) break;
    offset += pageSize;
  }

  return { exists: true, rows };
}

function buildInsertSql(table, rows) {
  if (!rows.length) return `-- Table public.${table}: 0 rows\n`;
  const lines = [`-- Table public.${table} (${rows.length} rows)`];
  for (const row of rows) {
    const cols = Object.keys(row);
    const colList = cols.map((c) => `"${c}"`).join(", ");
    const valList = cols.map((c) => sqlLiteral(row[c])).join(", ");
    lines.push(
      `INSERT INTO public."${table}" (${colList}) VALUES (${valList}) ON CONFLICT DO NOTHING;`
    );
  }
  // Reset bigserial/serial sequence if `id` is numeric
  if (typeof rows[0]?.id === "number") {
    lines.push(
      `SELECT setval(pg_get_serial_sequence('public.${table}', 'id'), COALESCE((SELECT MAX(id) FROM public."${table}"), 1), true);`
    );
  }
  lines.push("");
  return lines.join("\n");
}

async function listBucketFiles(bucketId, prefix = "") {
  const files = [];
  let offset = 0;
  const limit = 100;

  while (true) {
    const res = await fetch(`${SUPABASE_URL}/storage/v1/object/list/${bucketId}`, {
      method: "POST",
      headers: { ...HEADERS, "Content-Type": "application/json" },
      body: JSON.stringify({ prefix, limit, offset }),
    });
    if (!res.ok) break;
    const items = await res.json();
    if (!Array.isArray(items) || items.length === 0) break;

    for (const item of items) {
      const itemPath = prefix ? `${prefix}/${item.name}` : item.name;
      if (item.id === null) {
        // Folder -> recurse
        const subFiles = await listBucketFiles(bucketId, itemPath);
        files.push(...subFiles);
      } else {
        files.push(itemPath);
      }
    }
    if (items.length < limit) break;
    offset += limit;
  }

  return files;
}

async function downloadStorageBuckets(storageDir) {
  const bucketSummary = {};
  const res = await fetch(`${SUPABASE_URL}/storage/v1/bucket`, { headers: HEADERS });
  if (!res.ok) {
    console.warn(`⚠ Could not list storage buckets (${res.status})`);
    return bucketSummary;
  }

  const buckets = await res.json();
  if (!Array.isArray(buckets)) return bucketSummary;

  for (const bucket of buckets) {
    const bucketId = bucket.id || bucket.name;
    const files = await listBucketFiles(bucketId);
    let downloaded = 0;
    let failed = 0;

    for (const relPath of files) {
      const encodedPath = relPath
        .split("/")
        .map((seg) => encodeURIComponent(seg))
        .join("/");
      const fileUrl = `${SUPABASE_URL}/storage/v1/object/${encodeURIComponent(bucketId)}/${encodedPath}`;
      try {
        const fRes = await fetch(fileUrl, { headers: HEADERS });
        if (!fRes.ok) {
          failed++;
          continue;
        }
        const buf = Buffer.from(await fRes.arrayBuffer());
        const outFile = path.join(storageDir, bucketId, relPath);
        fs.mkdirSync(path.dirname(outFile), { recursive: true });
        fs.writeFileSync(outFile, buf);
        downloaded++;
      } catch {
        failed++;
      }
    }

    bucketSummary[bucketId] = {
      public: Boolean(bucket.public),
      totalFiles: files.length,
      downloaded,
      failed,
    };
    console.log(`  📦 Bucket "${bucketId}": ${downloaded}/${files.length} files downloaded`);
  }

  return bucketSummary;
}

function bundleMigrations(outPath) {
  const migrationsDir = path.join(ROOT_DIR, "supabase", "migrations");
  if (!fs.existsSync(migrationsDir)) return 0;
  const sqlFiles = fs
    .readdirSync(migrationsDir)
    .filter((f) => f.endsWith(".sql"))
    .sort();

  const chunks = [
    "-- ======================================================================",
    `-- Consolidated Schema Migrations Bundle (${sqlFiles.length} files)`,
    `-- Generated: ${new Date().toISOString()}`,
    "-- ======================================================================\n",
  ];

  for (const file of sqlFiles) {
    const content = fs.readFileSync(path.join(migrationsDir, file), "utf8");
    chunks.push(`-- >>> BEGIN MIGRATION: ${file}\n${content}\n-- <<< END MIGRATION: ${file}\n`);
  }

  fs.writeFileSync(outPath, chunks.join("\n"), "utf8");
  return sqlFiles.length;
}

async function main() {
  const tag = timestampTag();
  const backupDir = path.join(ROOT_DIR, "backups", `supabase_backup_${tag}`);
  const dataDir = path.join(backupDir, "data");
  const storageDir = path.join(backupDir, "storage");
  fs.mkdirSync(dataDir, { recursive: true });
  fs.mkdirSync(storageDir, { recursive: true });

  console.log(`\n🚀 Starting Full Supabase Backup -> ${backupDir}\n`);

  // 1. Database tables
  const tables = await discoverPublicTables();
  const tableSummary = {};
  const sqlParts = [
    "-- ======================================================================",
    `-- TCAA Slaughterhouse Data Restore SQL`,
    `-- Source: ${SUPABASE_URL}`,
    `-- Generated: ${new Date().toISOString()}`,
    "-- ======================================================================\n",
    "BEGIN;\n",
  ];

  for (const table of tables) {
    const result = await fetchAllRows(table);
    if (!result.exists) {
      if (result.error) {
        console.log(`  ⏭ Skipped "${table}" (${result.status})`);
      }
      continue;
    }
    fs.writeFileSync(
      path.join(dataDir, `${table}.json`),
      JSON.stringify(result.rows, null, 2),
      "utf8"
    );
    sqlParts.push(buildInsertSql(table, result.rows));
    tableSummary[table] = result.rows.length;
    console.log(`  ✅ Table "${table}": ${result.rows.length} rows exported`);
  }

  sqlParts.push("COMMIT;\n");
  fs.writeFileSync(path.join(backupDir, "restore_data.sql"), sqlParts.join("\n"), "utf8");

  // 2. Consolidated schema migrations
  const migrationCount = bundleMigrations(path.join(backupDir, "all_migrations_bundle.sql"));
  console.log(`\n  📜 Bundled ${migrationCount} schema migrations -> all_migrations_bundle.sql\n`);

  // 3. Storage buckets
  const storageSummary = await downloadStorageBuckets(storageDir);

  // 4. Manifest
  const manifest = {
    created_at: new Date().toISOString(),
    source_url: SUPABASE_URL,
    tables: tableSummary,
    total_rows: Object.values(tableSummary).reduce((a, b) => a + b, 0),
    migrations_bundled: migrationCount,
    storage: storageSummary,
  };
  fs.writeFileSync(
    path.join(backupDir, "manifest.json"),
    JSON.stringify(manifest, null, 2),
    "utf8"
  );

  console.log(
    `\n🎉 Backup complete! Total rows: ${manifest.total_rows} across ${Object.keys(tableSummary).length} tables.\n` +
      `   Saved to: ${backupDir}\n`
  );
}

main().catch((err) => {
  console.error("❌ Backup failed:", err);
  process.exit(1);
});
