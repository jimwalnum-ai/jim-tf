import {
  SQSClient,
  ReceiveMessageCommand,
  DeleteMessageBatchCommand,
  GetQueueUrlCommand,
  type Message,
} from "@aws-sdk/client-sqs";
import {
  SecretsManagerClient,
  GetSecretValueCommand,
} from "@aws-sdk/client-secrets-manager";
import { randomBytes, randomUUID } from "node:crypto";
import { Pool } from "pg";

const QUEUE_NAME = process.env.FACTOR_RESULT_QUEUE_NAME ?? "SQS_FACTOR_RESULT_TS_DEV";
const VISIBILITY_TIMEOUT_SECONDS = parseInt(process.env.SQS_VISIBILITY_TIMEOUT_SECONDS ?? "300", 10);
const BATCH_SIZE = parseInt(process.env.SQS_BATCH_SIZE ?? "10", 10);
const WORKER_COUNT = parseInt(process.env.PERSIST_WORKER_COUNT ?? "8", 10);

const region = process.env.AWS_DEFAULT_REGION ?? "us-east-1";
const sqs = new SQSClient({ region });
const sm = new SecretsManagerClient({ region });

interface SecretData {
  host: string;
  port?: string;
  username: string;
  password: string;
  database?: string;
}

function uuid7(timestampMs?: number): string {
  const ts = BigInt(timestampMs ?? Date.now()) & ((1n << 48n) - 1n);
  const randA = BigInt(`0x${randomBytes(2).toString("hex")}`) & ((1n << 12n) - 1n);
  const randB = BigInt(`0x${randomBytes(8).toString("hex")}`) & ((1n << 62n) - 1n);
  const uuidInt = (ts << 80n) | (0x7n << 76n) | (randA << 64n) | (0x2n << 62n) | randB;
  const hex = uuidInt.toString(16).padStart(32, "0");
  return [hex.slice(0, 8), hex.slice(8, 12), hex.slice(12, 16), hex.slice(16, 20), hex.slice(20)].join("-");
}

function parseConnParams(secret: SecretData): { host: string; port: number; user: string; password: string; ssl: { rejectUnauthorized: boolean } } {
  let host = secret.host;
  let port = secret.port;
  if (host && host.includes(":")) {
    const idx = host.lastIndexOf(":");
    const hostPort = host.slice(idx + 1);
    if (/^\d+$/.test(hostPort)) {
      host = host.slice(0, idx);
      if (!port) port = hostPort;
    }
  }
  return { host, port: parseInt(port ?? "5432", 10), user: secret.username, password: secret.password, ssl: { rejectUnauthorized: false } };
}

function parseMessage(msg: Message): {
  sequence: string;
  data: string;
  receiptHandle: string;
  scheme: string;
  persistedAtMs: number;
} {
  const pulledAtMs = Date.now();
  const attrs = msg.MessageAttributes!;
  const sentTimestamp = parseInt(msg.Attributes!["SentTimestamp"]!, 10);
  const scheme = parseInt(attrs["Scheme"].StringValue!, 10);
  const sequenceRaw = attrs["Sequence"]?.StringValue;
  const sentTimeRaw = attrs["SentTime"]?.StringValue;
  const pulledTimeRaw = attrs["PulledTime"]?.StringValue;
  const factorTimeRaw = attrs["FactorTime"]?.StringValue;
  const result = JSON.parse(attrs["Result"].StringValue!);
  let persistedAtMs = Date.now();

  const pullToPersistMs =
    pulledTimeRaw && /^\d+$/.test(pulledTimeRaw)
      ? persistedAtMs - parseInt(pulledTimeRaw, 10)
      : 0;

  const runtime = attrs["Runtime"]?.StringValue ?? "typescript";

  const data: Record<string, unknown> = {
    factor: parseInt(attrs["Factor"].StringValue!, 10),
    result,
    scheme,
    ms: 0,
    queue_to_db_ms: 0,
    pulled_at_ms: pulledAtMs,
    persisted_at_ms: persistedAtMs,
    pull_to_persist_ms: pullToPersistMs,
    runtime,
  };

  if (factorTimeRaw && /^\d+$/.test(factorTimeRaw)) {
    data.factor_time_ms = parseInt(factorTimeRaw, 10);
  }
  if (sequenceRaw) data.sequence_raw = sequenceRaw;
  if (sentTimeRaw) {
    data.sent_time = sentTimeRaw;
    if (/^\d+$/.test(sentTimeRaw)) {
      persistedAtMs = Date.now();
      data.sent_to_persist_ms = persistedAtMs - parseInt(sentTimeRaw, 10);
    }
  }
  if (pulledTimeRaw) data.pulled_time = pulledTimeRaw;

  const tsForUuid =
    sentTimeRaw && /^\d+$/.test(sentTimeRaw) ? parseInt(sentTimeRaw, 10) : sentTimestamp;
  const sequence = uuid7(tsForUuid);

  return {
    sequence,
    data: JSON.stringify(data),
    receiptHandle: msg.ReceiptHandle!,
    scheme: String(scheme),
    persistedAtMs,
  };
}

const SUMMARY_UPSERT = `
  INSERT INTO factors_ts (sequence, data) VALUES ($1, $2::jsonb)
  ON CONFLICT (sequence) DO NOTHING
`;

const SCHEME_UPSERT = `
  INSERT INTO scheme_summary_ts (scheme, total_count, first_persisted_at_ms, last_persisted_at_ms)
  VALUES ($1, $2, $3, $4)
  ON CONFLICT (scheme) DO UPDATE SET
    total_count = scheme_summary_ts.total_count + EXCLUDED.total_count,
    first_persisted_at_ms = LEAST(scheme_summary_ts.first_persisted_at_ms, EXCLUDED.first_persisted_at_ms),
    last_persisted_at_ms = GREATEST(scheme_summary_ts.last_persisted_at_ms, EXCLUDED.last_persisted_at_ms)
`;

async function resolveQueueUrl(name: string): Promise<string> {
  if (name.startsWith("https://")) return name;
  const resp = await sqs.send(new GetQueueUrlCommand({ QueueName: name }));
  return resp.QueueUrl!;
}

async function ensureSchema(pool: Pool): Promise<void> {
  const client = await pool.connect();
  try {
    await client.query(`
      CREATE TABLE IF NOT EXISTS factors_ts (
        sequence UUID PRIMARY KEY,
        data JSONB NOT NULL
      )
    `);
    await client.query(`
      CREATE TABLE IF NOT EXISTS scheme_summary_ts (
        scheme TEXT PRIMARY KEY,
        total_count BIGINT NOT NULL DEFAULT 0,
        first_persisted_at_ms BIGINT,
        last_persisted_at_ms BIGINT
      )
    `);
  } finally {
    client.release();
  }
}

async function worker(workerId: number, pool: Pool, queueUrl: string): Promise<void> {
  console.log(`[worker-${workerId}] started`);

  while (true) {
    const resp = await sqs.send(
      new ReceiveMessageCommand({
        QueueUrl: queueUrl,
        AttributeNames: ["All"],
        MaxNumberOfMessages: BATCH_SIZE,
        MessageAttributeNames: ["All"],
        VisibilityTimeout: VISIBILITY_TIMEOUT_SECONDS,
        WaitTimeSeconds: 20,
      }),
    );

    const messages = resp.Messages ?? [];
    if (messages.length === 0) break;

    const rows: { seq: string; data: string }[] = [];
    const receipts: string[] = [];
    const schemeBatches = new Map<string, { count: number; minMs: number; maxMs: number }>();

    for (const msg of messages) {
      try {
        const parsed = parseMessage(msg);
        rows.push({ seq: parsed.sequence, data: parsed.data });
        receipts.push(parsed.receiptHandle);

        const sb = schemeBatches.get(parsed.scheme);
        if (!sb) {
          schemeBatches.set(parsed.scheme, {
            count: 1,
            minMs: parsed.persistedAtMs,
            maxMs: parsed.persistedAtMs,
          });
        } else {
          sb.count++;
          if (parsed.persistedAtMs < sb.minMs) sb.minMs = parsed.persistedAtMs;
          if (parsed.persistedAtMs > sb.maxMs) sb.maxMs = parsed.persistedAtMs;
        }
      } catch (err) {
        console.error(`[worker-${workerId}] parse error:`, err);
      }
    }

    if (rows.length > 0) {
      const client = await pool.connect();
      try {
        await client.query("BEGIN");
        for (const row of rows) {
          await client.query(SUMMARY_UPSERT, [row.seq, row.data]);
        }
        for (const [scheme, sb] of schemeBatches) {
          await client.query(SCHEME_UPSERT, [scheme, sb.count, sb.minMs, sb.maxMs]);
        }
        await client.query("COMMIT");
      } catch (err) {
        await client.query("ROLLBACK");
        throw err;
      } finally {
        client.release();
      }
    }

    for (let i = 0; i < receipts.length; i += 10) {
      const batch = receipts.slice(i, i + 10).map((r, j) => ({ Id: String(j), ReceiptHandle: r }));
      await sqs.send(new DeleteMessageBatchCommand({ QueueUrl: queueUrl, Entries: batch }));
    }

    console.log(`[worker-${workerId}] persisted ${rows.length} messages`);
  }

  console.log(`[worker-${workerId}] done (queue empty)`);
}

async function main(): Promise<void> {
  const secretResp = await sm.send(
    new GetSecretValueCommand({ SecretId: process.env.RDS_SECRET_NAME ?? "cs-factor-credentials" }),
  );
  const secretData: SecretData = JSON.parse(secretResp.SecretString!);
  const connParams = parseConnParams(secretData);
  const dbName = process.env.FACTOR_DB_NAME ?? secretData.database ?? "factors";

  const pool = new Pool({ ...connParams, database: dbName, max: WORKER_COUNT + 2 });

  await ensureSchema(pool);

  const queueUrl = await resolveQueueUrl(QUEUE_NAME);

  const workers = Array.from({ length: WORKER_COUNT }, (_, i) => worker(i, pool, queueUrl));
  await Promise.all(workers);

  await pool.end();
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
