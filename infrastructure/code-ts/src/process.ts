import {
  SQSClient,
  ReceiveMessageCommand,
  SendMessageBatchCommand,
  DeleteMessageBatchCommand,
  GetQueueUrlCommand,
  type Message,
  type SendMessageBatchRequestEntry,
  type DeleteMessageBatchRequestEntry,
} from "@aws-sdk/client-sqs";

const QUEUE_NAME = process.env.FACTOR_QUEUE_NAME ?? "SQS_FACTOR_TS_DEV";
const RESULT_QUEUE_NAME = process.env.FACTOR_RESULT_QUEUE_NAME ?? "SQS_FACTOR_RESULT_TS_DEV";
const VISIBILITY_TIMEOUT_SECONDS = parseInt(process.env.SQS_VISIBILITY_TIMEOUT_SECONDS ?? "60", 10);
const RECEIVER_CONCURRENCY = parseInt(process.env.RECEIVER_THREADS ?? "8", 10);

const sqs = new SQSClient({ region: process.env.AWS_DEFAULT_REGION ?? "us-east-1" });

function doFactor(n: number): number[] {
  if (n <= 1) return [];
  const small: number[] = [];
  const large: number[] = [];
  const limit = Math.floor(Math.sqrt(n));
  for (let i = 1; i <= limit; i++) {
    if (n % i === 0) {
      if (i !== n) small.push(i);
      const other = n / i;
      if (other !== i && other !== n) large.push(other);
    }
  }
  return [...small, ...large.reverse()];
}

function timedFactor(n: number): { result: number[]; elapsedMs: number } {
  const t0 = performance.now();
  const result = doFactor(n);
  const elapsedMs = Math.round(performance.now() - t0);
  return { result, elapsedMs };
}

function buildEntry(
  index: number,
  msg: Message,
  factorList: number[],
  factorTimeMs: number,
): { send: SendMessageBatchRequestEntry; del: DeleteMessageBatchRequestEntry } {
  const pulledTimeMs = Date.now();
  const factor = msg.MessageAttributes!["Factor"].StringValue!;
  const scheme = msg.MessageAttributes!["Scheme"].StringValue!;
  const sentTime = msg.Attributes!["SentTimestamp"]!;
  const seq = msg.MessageId!;
  const ms = Math.max(0, pulledTimeMs - parseInt(sentTime, 10));

  const runtime = msg.MessageAttributes!["Runtime"]?.StringValue ?? "typescript";

  return {
    send: {
      Id: String(index),
      DelaySeconds: 0,
      MessageAttributes: {
        Result:     { DataType: "String", StringValue: JSON.stringify(factorList) },
        SentTime:   { DataType: "String", StringValue: sentTime },
        PulledTime: { DataType: "String", StringValue: String(pulledTimeMs) },
        Sequence:   { DataType: "String", StringValue: seq },
        Factor:     { DataType: "String", StringValue: factor },
        Scheme:     { DataType: "String", StringValue: scheme },
        ms:         { DataType: "Number", StringValue: String(ms) },
        FactorTime: { DataType: "Number", StringValue: String(factorTimeMs) },
        Runtime:    { DataType: "String", StringValue: runtime },
      },
      MessageBody: "Factor",
    },
    del: { Id: String(index), ReceiptHandle: msg.ReceiptHandle! },
  };
}

async function resolveQueueUrl(name: string): Promise<string> {
  if (name.startsWith("https://")) return name;
  const resp = await sqs.send(new GetQueueUrlCommand({ QueueName: name }));
  return resp.QueueUrl!;
}

async function receiverLoop(threadId: number, queueUrl: string, sendQueueUrl: string): Promise<void> {
  let emptyPolls = 0;
  let processed = 0;

  while (true) {
    const resp = await sqs.send(
      new ReceiveMessageCommand({
        QueueUrl: queueUrl,
        AttributeNames: ["All"],
        MaxNumberOfMessages: 10,
        MessageAttributeNames: ["All"],
        VisibilityTimeout: VISIBILITY_TIMEOUT_SECONDS,
        WaitTimeSeconds: 20,
      }),
    );

    const messages = resp.Messages ?? [];
    if (messages.length === 0) {
      emptyPolls++;
      if (emptyPolls >= 3) break;
      continue;
    }
    emptyPolls = 0;

    const sendEntries: SendMessageBatchRequestEntry[] = [];
    const deleteEntries: DeleteMessageBatchRequestEntry[] = [];

    for (let idx = 0; idx < messages.length; idx++) {
      const msg = messages[idx];
      const factor = parseInt(msg.MessageAttributes!["Factor"].StringValue!, 10);
      const { result, elapsedMs } = timedFactor(factor);
      const { send, del } = buildEntry(idx, msg, result, elapsedMs);
      sendEntries.push(send);
      deleteEntries.push(del);
    }

    const sendResp = await sqs.send(
      new SendMessageBatchCommand({ QueueUrl: sendQueueUrl, Entries: sendEntries }),
    );

    const failedIds = new Set((sendResp.Failed ?? []).map((f) => f.Id));
    if (failedIds.size > 0) {
      console.error(`thread=${threadId} send_failures=${failedIds.size}`);
    }

    const toDelete = deleteEntries.filter((e) => !failedIds.has(e.Id));
    if (toDelete.length > 0) {
      await sqs.send(new DeleteMessageBatchCommand({ QueueUrl: queueUrl, Entries: toDelete }));
    }

    processed += messages.length;
    if (processed % 100 < 11) {
      console.log(`thread=${threadId} processed=${processed}`);
    }
  }

  console.log(`thread=${threadId} done processed=${processed}`);
}

async function main(): Promise<void> {
  const queueUrl = await resolveQueueUrl(QUEUE_NAME);
  const sendQueueUrl = await resolveQueueUrl(RESULT_QUEUE_NAME);

  const workers = Array.from({ length: RECEIVER_CONCURRENCY }, (_, i) =>
    receiverLoop(i, queueUrl, sendQueueUrl),
  );
  await Promise.all(workers);
  console.log("all_threads_done");
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
