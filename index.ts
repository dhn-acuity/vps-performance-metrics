import { Hono } from "hono";
import os from "os";
import process from "process";
import fs from "fs";
import { monitorEventLoopDelay, performance } from "perf_hooks";

const app = new Hono();

/**
 * =========================
 * Config
 * =========================
 */
const WINDOW_SECONDS = 10;
const RESET_INTERVAL_SECONDS = 60; // set 0 to disable
const ELU_STOP_THRESHOLD = 0.9;

/**
 * =========================
 * Event loop lag monitor
 * =========================
 */
const eld = monitorEventLoopDelay({ resolution: 10 }); // 10ms resolution
eld.enable();

function getEventLoopLag() {
  return {
    minMs: Number((eld.min / 1e6).toFixed(2)),
    maxMs: Number((eld.max / 1e6).toFixed(2)),
    meanMs: Number((eld.mean / 1e6).toFixed(2)),
    p95Ms: Number((eld.percentile(95) / 1e6).toFixed(2)),
  };
}

/**
 * =========================
 * ELU (Event Loop Utilization)
 * =========================
 */
let lastELU = performance.eventLoopUtilization();

function getELU() {
  const current = performance.eventLoopUtilization(lastELU);
  lastELU = current;
  return {
    utilization: Number(current.utilization.toFixed(3)),
    activeMs: Math.round(current.active),
    idleMs: Math.round(current.idle),
  };
}

/**
 * =========================
 * CPU + Memory
 * =========================
 */
type ProcessCpuSnapshot = {
  user: number; // microseconds
  system: number; // microseconds
  time: number; // timestamp in ms
};

function takeProcessCpuSnapshot(): ProcessCpuSnapshot {
  const usage = process.cpuUsage();
  return {
    user: usage.user,
    system: usage.system,
    time: Date.now(),
  };
}

let lastProcessCpu = takeProcessCpuSnapshot();

function getCpuUsage() {
  const current = takeProcessCpuSnapshot();
  const cpus = os.cpus();

  // Calculate elapsed wall-clock time in microseconds
  const elapsedMs = current.time - lastProcessCpu.time;
  const elapsedUs = elapsedMs * 1000;

  // Calculate CPU time used by process (user + system) in microseconds
  const userDelta = current.user - lastProcessCpu.user;
  const systemDelta = current.system - lastProcessCpu.system;
  const cpuTimeUs = userDelta + systemDelta;

  // Update for next call
  lastProcessCpu = current;

  // Avoid division by zero
  if (elapsedUs === 0) {
    return {
      cores: cpus.length,
      processUsagePercent: 0,
      systemUsagePercent: 0,
    };
  }

  // Process CPU % = (cpu_time / elapsed_time) * 100
  // This can exceed 100% on multi-core systems (e.g., 200% = using 2 cores fully)
  const processUsagePercent = Number(((cpuTimeUs / elapsedUs) * 100).toFixed(2));

  // Get system-wide CPU for reference
  const sysCpus = os.cpus();
  let sysIdle = 0;
  let sysTotal = 0;
  for (const cpu of sysCpus) {
    for (const type in cpu.times) {
      sysTotal += cpu.times[type as keyof typeof cpu.times];
    }
    sysIdle += cpu.times.idle;
  }
  const systemUsagePercent = Number(
    (((sysTotal - sysIdle) / sysTotal) * 100).toFixed(2)
  );

  return {
    cores: cpus.length,
    processUsagePercent,
    systemUsagePercent,
  };
}

function getMemoryUsage() {
  const total = os.totalmem();
  const free = os.freemem();
  const used = total - free;

  return {
    totalMB: Math.round(total / 1024 / 1024),
    usedMB: Math.round(used / 1024 / 1024),
    freeMB: Math.round(free / 1024 / 1024),
    usagePercent: Number(((used / total) * 100).toFixed(2)),
  };
}

/**
 * =========================
 * Network throughput (Linux)
 * Reads /proc/net/dev and returns RX/TX Mbps
 * =========================
 */
type NetSnap = { rx: number; tx: number; time: number } | null;

function readNet(): NetSnap {
  try {
    // Only on Linux
    if (process.platform !== "linux") return null;
    const data = fs.readFileSync("/proc/net/dev", "utf8");
    const lines = data.split("\n").slice(2);

    let rx = 0;
    let tx = 0;

    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed) continue;

      // Format: iface: rxbytes ... txbytes ...
      // We'll split whitespace; parts[1]=rx bytes, parts[9]=tx bytes
      const parts = trimmed.replace(":", " ").split(/\s+/);
      if (parts.length < 10) continue;

      rx += Number(parts[1]);
      tx += Number(parts[9]);
    }

    return { rx, tx, time: Date.now() };
  } catch {
    return null;
  }
}

let lastNet: NetSnap = readNet();

function getNetworkThroughput() {
  const current = readNet();
  if (!current || !lastNet) {
    lastNet = current;
    return null;
  }

  const dt = (current.time - lastNet.time) / 1000;
  if (dt <= 0) {
    lastNet = current;
    return { rxMbps: 0, txMbps: 0 };
  }

  const rxMbps = ((current.rx - lastNet.rx) * 8) / dt / 1e6;
  const txMbps = ((current.tx - lastNet.tx) * 8) / dt / 1e6;

  lastNet = current;

  return {
    rxMbps: Number(rxMbps.toFixed(2)),
    txMbps: Number(txMbps.toFixed(2)),
  };
}

/**
 * =========================
 * Sliding-window latency histogram (last WINDOW_SECONDS)
 * + auto reset every RESET_INTERVAL_SECONDS
 * =========================
 */
const latencyBucketsMs = [5, 10, 20, 50, 100, 200, 500, 1000];

type LatencyBucket = {
  count: number;
  samples: number[];
  histogram: Record<string, number>;
};

function createBucket(): LatencyBucket {
  const hist: Record<string, number> = {};
  for (const b of latencyBucketsMs) hist[`<=${b}ms`] = 0;
  hist[">1000ms"] = 0;
  return { count: 0, samples: [], histogram: hist };
}

const latencyWindow = new Map<number, LatencyBucket>(); // key = unix second

function recordLatency(ms: number) {
  const nowSec = Math.floor(Date.now() / 1000);

  let bucket = latencyWindow.get(nowSec);
  if (!bucket) {
    bucket = createBucket();
    latencyWindow.set(nowSec, bucket);
  }

  bucket.count++;
  bucket.samples.push(ms);

  for (const b of latencyBucketsMs) {
    if (ms <= b) {
      bucket.histogram[`<=${b}ms`]++;
      return;
    }
  }
  bucket.histogram[">1000ms"]++;
}

function cleanupOldBuckets() {
  const cutoff = Math.floor(Date.now() / 1000) - WINDOW_SECONDS;
  for (const key of latencyWindow.keys()) {
    if (key < cutoff) latencyWindow.delete(key);
  }
}

function percentileSorted(sorted: number[], p: number) {
  if (sorted.length === 0) return 0;
  const idx = Math.ceil((p / 100) * sorted.length) - 1;
  return sorted[Math.max(0, Math.min(idx, sorted.length - 1))];
}

function getSlidingLatencyStats() {
  cleanupOldBuckets();

  const combinedHistogram: Record<string, number> = {};
  for (const b of latencyBucketsMs) combinedHistogram[`<=${b}ms`] = 0;
  combinedHistogram[">1000ms"] = 0;

  let requests = 0;
  const allSamples: number[] = [];

  for (const bucket of latencyWindow.values()) {
    requests += bucket.count;
    allSamples.push(...bucket.samples);

    for (const k in bucket.histogram) {
      combinedHistogram[k] += bucket.histogram[k];
    }
  }

  allSamples.sort((a, b) => a - b);

  return {
    windowSeconds: WINDOW_SECONDS,
    requests,
    p50Ms: Math.round(percentileSorted(allSamples, 50)),
    p95Ms: Math.round(percentileSorted(allSamples, 95)),
    p99Ms: Math.round(percentileSorted(allSamples, 99)),
    histogram: combinedHistogram,
  };
}

function resetLatencyStats() {
  latencyWindow.clear();
}

if (RESET_INTERVAL_SECONDS > 0) {
  setInterval(() => {
    resetLatencyStats();
    console.log("[metrics] latency stats reset");
  }, RESET_INTERVAL_SECONDS * 1000).unref();
}

/**
 * =========================
 * Middleware: record per-request latency
 * =========================
 */
app.use("*", async (c, next) => {
  const start = performance.now();
  await next();
  const ms = performance.now() - start;
  recordLatency(ms);
});

/**
 * =========================
 * Routes
 * =========================
 */
app.get("/health", (c) => c.text("ok"));

app.get("/metrics", (c) => {
  const elu = getELU();
  const cpu = getCpuUsage();

  return c.json({
    cpu: {
      cores: cpu.cores,
      // Process CPU can exceed 100% on multi-core (e.g., 150% = 1.5 cores used)
      processUsagePercent: cpu.processUsagePercent,
      // System-wide CPU across all cores
      systemUsagePercent: cpu.systemUsagePercent,
    },
    memory: getMemoryUsage(),

    eventLoop: {
      lag: getEventLoopLag(),
      elu,
      overloaded: elu.utilization >= ELU_STOP_THRESHOLD,
      threshold: ELU_STOP_THRESHOLD,
    },

    latency: getSlidingLatencyStats(),

    network: getNetworkThroughput(), // null if not supported

    process: {
      pid: process.pid,
      rssMB: Math.round(process.memoryUsage().rss / 1024 / 1024),
      uptimeSec: Math.round(process.uptime()),
    },

    timestamp: new Date().toISOString(),
  });
});

export default app;
