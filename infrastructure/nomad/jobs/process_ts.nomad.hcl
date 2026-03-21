job "factor-process-ts" {
  datacenters = ["dc1"]
  region      = "us-east-1"
  type        = "service"

  group "process-ts" {
    count = 2

    restart {
      attempts = 10
      interval = "5m"
      delay    = "15s"
      mode     = "delay"
    }

    task "process-ts" {
      driver = "docker"

      config {
        image   = "node:22-slim"
        command = "/bin/sh"
        args    = ["-c", "cd /local && npm install --omit=dev && while true; do node process.js || true; sleep 30; done"]
      }

      template {
        destination = "local/package.json"
        data        = <<JSONEOF
{
  "name": "factor-ts-nomad",
  "private": true,
  "dependencies": {
    "@aws-sdk/client-sqs": "^3.750.0"
  }
}
JSONEOF
      }

      template {
        destination = "local/process.js"
        data        = <<JSEOF
"use strict";
const { SQSClient, ReceiveMessageCommand, SendMessageBatchCommand, DeleteMessageBatchCommand, GetQueueUrlCommand } = require("@aws-sdk/client-sqs");

const QUEUE_NAME = process.env.FACTOR_QUEUE_NAME || "SQS_FACTOR_TS_DEV";
const RESULT_QUEUE_NAME = process.env.FACTOR_RESULT_QUEUE_NAME || "SQS_FACTOR_RESULT_TS_DEV";
const VISIBILITY_TIMEOUT = parseInt(process.env.SQS_VISIBILITY_TIMEOUT_SECONDS || "60", 10);
const CONCURRENCY = parseInt(process.env.RECEIVER_THREADS || "8", 10);

const sqs = new SQSClient({ region: process.env.AWS_DEFAULT_REGION || "us-east-1" });

function doFactor(n) {
  if (n <= 1) return [];
  const small = [], large = [];
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

async function resolve(name) {
  if (name.startsWith("https://")) return name;
  const r = await sqs.send(new GetQueueUrlCommand({ QueueName: name }));
  return r.QueueUrl;
}

async function loop(tid, queueUrl, sendUrl) {
  let empty = 0, processed = 0;
  while (true) {
    const resp = await sqs.send(new ReceiveMessageCommand({
      QueueUrl: queueUrl, AttributeNames: ["All"], MaxNumberOfMessages: 10,
      MessageAttributeNames: ["All"], VisibilityTimeout: VISIBILITY_TIMEOUT, WaitTimeSeconds: 20,
    }));
    const msgs = resp.Messages || [];
    if (!msgs.length) { if (++empty >= 3) break; continue; }
    empty = 0;
    const send = [], del = [];
    for (let i = 0; i < msgs.length; i++) {
      const m = msgs[i];
      const factor = parseInt(m.MessageAttributes.Factor.StringValue, 10);
      const t0 = performance.now();
      const result = doFactor(factor);
      const elapsed = Math.round(performance.now() - t0);
      const now = Date.now();
      const sentTime = m.Attributes.SentTimestamp;
      const runtime = m.MessageAttributes.Runtime?.StringValue || "typescript";
      send.push({
        Id: String(i), DelaySeconds: 0, MessageBody: "Factor",
        MessageAttributes: {
          Result: { DataType: "String", StringValue: JSON.stringify(result) },
          SentTime: { DataType: "String", StringValue: sentTime },
          PulledTime: { DataType: "String", StringValue: String(now) },
          Sequence: { DataType: "String", StringValue: m.MessageId },
          Factor: { DataType: "String", StringValue: m.MessageAttributes.Factor.StringValue },
          Scheme: { DataType: "String", StringValue: m.MessageAttributes.Scheme.StringValue },
          Runtime: { DataType: "String", StringValue: runtime },
          ms: { DataType: "Number", StringValue: String(Math.max(0, now - parseInt(sentTime, 10))) },
          FactorTime: { DataType: "Number", StringValue: String(elapsed) },
        },
      });
      del.push({ Id: String(i), ReceiptHandle: m.ReceiptHandle });
    }
    const sr = await sqs.send(new SendMessageBatchCommand({ QueueUrl: sendUrl, Entries: send }));
    const failedIds = new Set((sr.Failed || []).map(f => f.Id));
    if (failedIds.size) console.error(`thread=$${tid} send_failures=$${failedIds.size}`);
    const toDelete = del.filter(e => !failedIds.has(e.Id));
    if (toDelete.length) await sqs.send(new DeleteMessageBatchCommand({ QueueUrl: queueUrl, Entries: toDelete }));
    processed += msgs.length;
    if (processed % 100 < 11) console.log(`thread=$${tid} processed=$${processed}`);
  }
  console.log(`thread=$${tid} done processed=$${processed}`);
}

(async () => {
  const queueUrl = await resolve(QUEUE_NAME);
  const sendUrl = await resolve(RESULT_QUEUE_NAME);
  await Promise.all(Array.from({ length: CONCURRENCY }, (_, i) => loop(i, queueUrl, sendUrl)));
  console.log("all_threads_done");
})().catch(e => { console.error("Fatal:", e); process.exit(1); });

JSEOF
      }

      env {
        AWS_DEFAULT_REGION       = "us-east-1"
        FACTOR_QUEUE_NAME        = "SQS_FACTOR_TS_DEV"
        FACTOR_RESULT_QUEUE_NAME = "SQS_FACTOR_RESULT_TS_DEV"
      }

      resources {
        cpu    = 512
        memory = 1024
      }

      service {
        name     = "factor-process-ts"
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
