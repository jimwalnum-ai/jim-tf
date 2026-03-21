job "factor-test-msg-ts" {
  datacenters = ["dc1"]
  region      = "us-east-1"
  type        = "batch"

  periodic {
    crons            = ["*/2 * * * *"]
    prohibit_overlap = true
  }

  group "test-msg-ts" {
    count = 1

    restart {
      attempts = 3
      interval = "5m"
      delay    = "15s"
      mode     = "fail"
    }

    task "test-msg-ts" {
      driver = "docker"

      config {
        image   = "node:22-slim"
        command = "/bin/sh"
        args    = ["-c", "cd /local && npm install --omit=dev && node test_msg.js"]
      }

      template {
        destination = "local/package.json"
        data        = <<JSONEOF
{
  "name": "factor-ts-test-msg-nomad",
  "private": true,
  "dependencies": {
    "@aws-sdk/client-sqs": "^3.750.0"
  }
}
JSONEOF
      }

      template {
        destination = "local/test_msg.js"
        data        = <<JSEOF
"use strict";
const { SQSClient, SendMessageBatchCommand, GetQueueUrlCommand } = require("@aws-sdk/client-sqs");

const QUEUE_NAME = process.env.FACTOR_QUEUE_NAME || "SQS_FACTOR_TS_DEV";
const INITIAL = 200000, TOPUP = 100000, INTERVAL = 180, LIMIT = 700000;
const SCHEME_MIN = 400000, SCHEME_MAX = 500000000, BATCH = 10, MAX_W = 40;
const sqs = new SQSClient({ region: process.env.AWS_DEFAULT_REGION || "us-east-1" });

const randInt = (a, b) => Math.floor(Math.random() * (b - a + 1)) + a;
const sleep = s => new Promise(r => setTimeout(r, s * 1000));

async function resolve(name) {
  if (name.startsWith("https://")) return name;
  return (await sqs.send(new GetQueueUrlCommand({ QueueName: name }))).QueueUrl;
}

async function sendBatch(url, entries) {
  const r = await sqs.send(new SendMessageBatchCommand({ QueueUrl: url, Entries: entries }));
  if ((r.Failed || []).length) throw new Error(`Failed: $${JSON.stringify(r.Failed)}`);
}

async function sendMessages(url, count, scheme, offset) {
  console.log(`sending count=$${count} scheme=$${scheme} offset=$${offset}`);
  const batches = [];
  for (let s = 0; s < count; s += BATCH) {
    if (s % 10000 === 0) console.log(`batch_start=$${offset + s}`);
    const n = Math.min(BATCH, count - s);
    const entries = [];
    for (let j = 0; j < n; j++) {
      entries.push({
        Id: String(offset + s + j), MessageBody: "test",
        MessageAttributes: {
          Factor: { DataType: "Number", StringValue: String(randInt(4, scheme)) },
          Scheme: { DataType: "Number", StringValue: String(scheme) },
          Runtime: { DataType: "String", StringValue: "typescript" },
        },
      });
    }
    batches.push(entries);
  }
  for (let i = 0; i < batches.length; i += MAX_W)
    await Promise.all(batches.slice(i, i + MAX_W).map(e => sendBatch(url, e)));
  console.log(`send_complete count=$${count} total_sent=$${offset + count}`);
}

(async () => {
  const url = await resolve(QUEUE_NAME);
  let scheme = randInt(SCHEME_MIN, SCHEME_MAX);
  console.log(`scheme=$${scheme} initial=$${INITIAL} topup=$${TOPUP} limit=$${LIMIT}`);
  let sent = 0;
  await sendMessages(url, INITIAL, scheme, sent); sent += INITIAL;
  while (sent < LIMIT) {
    console.log(`sleeping $${INTERVAL}s, total_sent=$${sent}`);
    await sleep(INTERVAL);
    scheme = randInt(SCHEME_MIN, SCHEME_MAX);
    const batch = Math.min(TOPUP, LIMIT - sent);
    await sendMessages(url, batch, scheme, sent); sent += batch;
  }
  console.log(`done total_sent=$${sent}`);
})().catch(e => { console.error("Fatal:", e); process.exit(1); });

JSEOF
      }

      env {
        AWS_DEFAULT_REGION = "us-east-1"
        FACTOR_QUEUE_NAME  = "SQS_FACTOR_TS_DEV"
      }

      resources {
        cpu    = 256
        memory = 512
      }
    }
  }
}
