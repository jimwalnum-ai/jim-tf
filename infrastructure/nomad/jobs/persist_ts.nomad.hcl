job "factor-persist-ts" {
  datacenters = ["dc1"]
  region      = "us-east-1"
  type        = "service"

  group "persist-ts" {
    count = 2

    restart {
      attempts = 10
      interval = "5m"
      delay    = "15s"
      mode     = "delay"
    }

    task "persist-ts" {
      driver = "docker"

      config {
        image   = "node:22-slim"
        command = "/bin/sh"
        args    = ["-c", "cd /local && npm install --omit=dev && while true; do node persist.js || true; sleep 30; done"]
      }

      template {
        destination = "local/package.json"
        data        = <<JSONEOF
{
  "name": "factor-ts-persist-nomad",
  "private": true,
  "dependencies": {
    "@aws-sdk/client-sqs": "^3.750.0",
    "@aws-sdk/client-secrets-manager": "^3.750.0",
    "pg": "^8.13.0"
  }
}
JSONEOF
      }

      template {
        destination = "local/persist.js"
        data        = <<JSEOF
"use strict";
const { SQSClient, ReceiveMessageCommand, DeleteMessageBatchCommand, GetQueueUrlCommand } = require("@aws-sdk/client-sqs");
const { SecretsManagerClient, GetSecretValueCommand } = require("@aws-sdk/client-secrets-manager");
const { randomBytes } = require("node:crypto");
const { Pool } = require("pg");

const QUEUE_NAME = process.env.FACTOR_RESULT_QUEUE_NAME || "SQS_FACTOR_RESULT_TS_DEV";
const VIS_TIMEOUT = parseInt(process.env.SQS_VISIBILITY_TIMEOUT_SECONDS || "300", 10);
const BATCH = 10;
const COMMIT_SIZE = parseInt(process.env.PERSIST_COMMIT_SIZE || "100", 10);
const WORKERS = parseInt(process.env.PERSIST_WORKER_COUNT || "8", 10);
const region = process.env.AWS_DEFAULT_REGION || "us-east-1";
const sqs = new SQSClient({ region });
const sm = new SecretsManagerClient({ region });

function uuid7(tsMs) {
  const ts = BigInt(tsMs ?? Date.now()) & ((1n << 48n) - 1n);
  const rA = BigInt("0x" + randomBytes(2).toString("hex")) & ((1n << 12n) - 1n);
  const rB = BigInt("0x" + randomBytes(8).toString("hex")) & ((1n << 62n) - 1n);
  const v = (ts << 80n) | (0x7n << 76n) | (rA << 64n) | (0x2n << 62n) | rB;
  const h = v.toString(16).padStart(32, "0");
  return [h.slice(0,8), h.slice(8,12), h.slice(12,16), h.slice(16,20), h.slice(20)].join("-");
}

function parseConn(s) {
  let host = s.host, port = s.port;
  if (host && host.includes(":")) {
    const i = host.lastIndexOf(":");
    const hp = host.slice(i + 1);
    if (/^\d+$/.test(hp)) { host = host.slice(0, i); if (!port) port = hp; }
  }
  return { host, port: parseInt(port || "5432", 10), user: s.username, password: s.password, ssl: { rejectUnauthorized: false } };
}

function parseMsg(msg) {
  const a = msg.MessageAttributes;
  const sentTs = parseInt(msg.Attributes.SentTimestamp, 10);
  const scheme = parseInt(a.Scheme.StringValue, 10);
  const runtime = a.Runtime?.StringValue || "typescript";
  const sentRaw = a.SentTime?.StringValue;
  const pulledRaw = a.PulledTime?.StringValue;
  const factorRaw = a.FactorTime?.StringValue;
  const result = JSON.parse(a.Result.StringValue);
  const now = Date.now();
  const pullToPersist = pulledRaw && /^\d+$/.test(pulledRaw) ? now - parseInt(pulledRaw, 10) : 0;
  const data = {
    factor: parseInt(a.Factor.StringValue, 10), result, scheme, runtime, ms: 0,
    queue_to_db_ms: 0, pulled_at_ms: now, persisted_at_ms: now, pull_to_persist_ms: pullToPersist,
  };
  if (factorRaw && /^\d+$/.test(factorRaw)) data.factor_time_ms = parseInt(factorRaw, 10);
  if (a.Sequence?.StringValue) data.sequence_raw = a.Sequence.StringValue;
  if (sentRaw) { data.sent_time = sentRaw; if (/^\d+$/.test(sentRaw)) data.sent_to_persist_ms = Date.now() - parseInt(sentRaw, 10); }
  if (pulledRaw) data.pulled_time = pulledRaw;
  const tsForUuid = sentRaw && /^\d+$/.test(sentRaw) ? parseInt(sentRaw, 10) : sentTs;
  return { sequence: uuid7(tsForUuid), data: JSON.stringify(data), receipt: msg.ReceiptHandle, scheme: String(scheme), tsMs: now };
}

async function resolve(name) {
  if (name.startsWith("https://")) return name;
  return (await sqs.send(new GetQueueUrlCommand({ QueueName: name }))).QueueUrl;
}

async function flush(id, pool, queueUrl, rows, receipts, schemes) {
  if (!rows.length) return;
  const c = await pool.connect();
  try {
    await c.query("BEGIN");
    for (const r of rows) await c.query("INSERT INTO factors_ts (sequence, data) VALUES ($1, $2::jsonb) ON CONFLICT (sequence) DO NOTHING", [r.sequence, r.data]);
    for (const [s, sb] of schemes) await c.query(`INSERT INTO scheme_summary_ts (scheme, total_count, first_persisted_at_ms, last_persisted_at_ms) VALUES ($1,$2,$3,$4) ON CONFLICT (scheme) DO UPDATE SET total_count = scheme_summary_ts.total_count + EXCLUDED.total_count, first_persisted_at_ms = LEAST(scheme_summary_ts.first_persisted_at_ms, EXCLUDED.first_persisted_at_ms), last_persisted_at_ms = GREATEST(scheme_summary_ts.last_persisted_at_ms, EXCLUDED.last_persisted_at_ms)`, [s, sb.count, sb.min, sb.max]);
    await c.query("COMMIT");
  } catch (e) { await c.query("ROLLBACK"); throw e; } finally { c.release(); }
  for (let i = 0; i < receipts.length; i += 10) {
    const batch = receipts.slice(i, i + 10).map((r, j) => ({ Id: String(j), ReceiptHandle: r }));
    await sqs.send(new DeleteMessageBatchCommand({ QueueUrl: queueUrl, Entries: batch }));
  }
  console.log(`[worker-$${id}] persisted $${rows.length} messages`);
}

async function worker(id, pool, queueUrl) {
  console.log(`[worker-$${id}] started`);
  let rows = [], receipts = [], schemes = new Map();
  while (true) {
    const wait = rows.length ? 0 : 20;
    const resp = await sqs.send(new ReceiveMessageCommand({
      QueueUrl: queueUrl, AttributeNames: ["All"], MaxNumberOfMessages: BATCH,
      MessageAttributeNames: ["All"], VisibilityTimeout: VIS_TIMEOUT, WaitTimeSeconds: wait,
    }));
    const msgs = resp.Messages || [];
    if (!msgs.length) {
      await flush(id, pool, queueUrl, rows, receipts, schemes);
      if (wait === 20) break;
      rows = []; receipts = []; schemes = new Map();
      continue;
    }
    for (const m of msgs) {
      try {
        const p = parseMsg(m);
        rows.push(p); receipts.push(p.receipt);
        const sb = schemes.get(p.scheme);
        if (!sb) schemes.set(p.scheme, { count: 1, min: p.tsMs, max: p.tsMs });
        else { sb.count++; if (p.tsMs < sb.min) sb.min = p.tsMs; if (p.tsMs > sb.max) sb.max = p.tsMs; }
      } catch (e) { console.error(`[worker-$${id}] parse error:`, e); }
    }
    if (rows.length >= COMMIT_SIZE) {
      await flush(id, pool, queueUrl, rows, receipts, schemes);
      rows = []; receipts = []; schemes = new Map();
    }
  }
  console.log(`[worker-$${id}] done (queue empty)`);
}

(async () => {
  const sec = await sm.send(new GetSecretValueCommand({ SecretId: process.env.RDS_SECRET_NAME || "cs-factor-credentials" }));
  const sd = JSON.parse(sec.SecretString);
  const cp = parseConn(sd);
  const dbName = process.env.FACTOR_DB_NAME || sd.database || "factors";
  const pool = new Pool({ ...cp, database: dbName, max: WORKERS + 2 });
  const c = await pool.connect();
  await c.query("CREATE TABLE IF NOT EXISTS factors_ts (sequence UUID PRIMARY KEY, data JSONB NOT NULL)");
  await c.query("CREATE TABLE IF NOT EXISTS scheme_summary_ts (scheme TEXT PRIMARY KEY, total_count BIGINT NOT NULL DEFAULT 0, first_persisted_at_ms BIGINT, last_persisted_at_ms BIGINT)");
  c.release();
  const queueUrl = await resolve(QUEUE_NAME);
  await Promise.all(Array.from({ length: WORKERS }, (_, i) => worker(i, pool, queueUrl)));
  await pool.end();
})().catch(e => { console.error("Fatal:", e); process.exit(1); });

JSEOF
      }

      env {
        AWS_DEFAULT_REGION       = "us-east-1"
        FACTOR_RESULT_QUEUE_NAME = "SQS_FACTOR_RESULT_TS_DEV"
        RDS_SECRET_NAME          = "cs-factor-credentials"
      }

      resources {
        cpu    = 512
        memory = 1024
      }

      service {
        name     = "factor-persist-ts"
        provider = "consul"

        check {
          type     = "script"
          command  = "/bin/sh"
          args     = ["-c", "kill -0 1"]
          interval = "30s"
          timeout  = "5s"
        }
      }
    }
  }
}
