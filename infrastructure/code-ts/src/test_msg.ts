import {
  SQSClient,
  SendMessageBatchCommand,
  GetQueueUrlCommand,
  type SendMessageBatchRequestEntry,
} from "@aws-sdk/client-sqs";

const QUEUE_NAME = process.env.FACTOR_QUEUE_NAME ?? "SQS_FACTOR_TS_DEV";
const INITIAL_MESSAGES = parseInt(process.env.INITIAL_MESSAGES ?? "200000", 10);
const TOPUP_MESSAGES = parseInt(process.env.TOPUP_MESSAGES ?? "100000", 10);
const TOPUP_INTERVAL_SECONDS = parseInt(process.env.TOPUP_INTERVAL_SECONDS ?? "180", 10);
const TOTAL_LIMIT = parseInt(process.env.TOTAL_LIMIT ?? "700000", 10);
const SCHEME_MIN = 400_000;
const SCHEME_MAX = 500_000_000;
const BATCH_SIZE = 10;
const MAX_WORKERS = parseInt(process.env.MAX_WORKERS ?? "40", 10);

const sqs = new SQSClient({ region: process.env.AWS_DEFAULT_REGION ?? "us-east-1" });

function randInt(min: number, max: number): number {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function pickScheme(): number {
  return randInt(SCHEME_MIN, SCHEME_MAX);
}

function buildEntries(startIndex: number, count: number, scheme: number): SendMessageBatchRequestEntry[] {
  const entries: SendMessageBatchRequestEntry[] = [];
  for (let offset = 0; offset < count; offset++) {
    entries.push({
      Id: String(startIndex + offset),
      MessageBody: "test",
      MessageAttributes: {
        Factor: { DataType: "Number", StringValue: String(randInt(4, scheme)) },
        Scheme: { DataType: "Number", StringValue: String(scheme) },
        Runtime: { DataType: "String", StringValue: "typescript" },
      },
    });
  }
  return entries;
}

async function resolveQueueUrl(name: string): Promise<string> {
  if (name.startsWith("https://")) return name;
  const resp = await sqs.send(new GetQueueUrlCommand({ QueueName: name }));
  return resp.QueueUrl!;
}

async function sendBatch(queueUrl: string, entries: SendMessageBatchRequestEntry[]): Promise<void> {
  const resp = await sqs.send(new SendMessageBatchCommand({ QueueUrl: queueUrl, Entries: entries }));
  const failed = resp.Failed ?? [];
  if (failed.length > 0) {
    throw new Error(`Failed to send ${failed.length} messages: ${JSON.stringify(failed)}`);
  }
}

async function sendMessages(queueUrl: string, count: number, scheme: number, offset = 0): Promise<void> {
  console.log(`sending count=${count} scheme=${scheme} offset=${offset}`);

  const batches: SendMessageBatchRequestEntry[][] = [];
  for (let start = 0; start < count; start += BATCH_SIZE) {
    if (start % 10000 === 0) {
      console.log(`batch_start=${offset + start}`);
    }
    const batchCount = Math.min(BATCH_SIZE, count - start);
    batches.push(buildEntries(offset + start, batchCount, scheme));
  }

  for (let i = 0; i < batches.length; i += MAX_WORKERS) {
    const chunk = batches.slice(i, i + MAX_WORKERS);
    await Promise.all(chunk.map((entries) => sendBatch(queueUrl, entries)));
  }

  console.log(`send_complete count=${count} total_sent=${offset + count}`);
}

function sleep(seconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, seconds * 1000));
}

async function main(): Promise<void> {
  const queueUrl = await resolveQueueUrl(QUEUE_NAME);

  let scheme = pickScheme();
  console.log(`scheme=${scheme} initial=${INITIAL_MESSAGES} topup=${TOPUP_MESSAGES} limit=${TOTAL_LIMIT}`);

  let totalSent = 0;

  await sendMessages(queueUrl, INITIAL_MESSAGES, scheme, totalSent);
  totalSent += INITIAL_MESSAGES;

  while (totalSent < TOTAL_LIMIT) {
    console.log(`sleeping ${TOPUP_INTERVAL_SECONDS}s before next top-up, total_sent=${totalSent}`);
    await sleep(TOPUP_INTERVAL_SECONDS);
    scheme = pickScheme();
    const remaining = TOTAL_LIMIT - totalSent;
    const batch = Math.min(TOPUP_MESSAGES, remaining);
    await sendMessages(queueUrl, batch, scheme, totalSent);
    totalSent += batch;
  }

  console.log(`done total_sent=${totalSent}`);
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
