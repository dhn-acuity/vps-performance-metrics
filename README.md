# VPS Performance Metrics

A production-grade Dockerized Hono.js service for measuring VPS performance with comprehensive metrics including CPU, RAM, event loop lag, ELU, and network throughput.

## Features

- ✅ **CPU & Memory Usage**: Real-time system resource monitoring
- ✅ **Event Loop Lag**: Min/Mean/P95/Max latency tracking
- ✅ **Event Loop Utilization (ELU)**: Detect saturation (auto-stop at 0.9)
- ✅ **Sliding Window Latency**: Last 10s histogram with P50/P95/P99
- ✅ **Network Throughput**: RX/TX Mbps via `/proc/net/dev` (Linux)
- ✅ **Auto-stop Protection**: Prevents over-testing when ELU threshold reached

## Architecture

```
AWS EC2 (load generator) ───HTTP───▶ VPS (metrics service)
                                      ├─ CPU
                                      ├─ RAM
                                      ├─ Event loop lag
                                      ├─ ELU
                                      └─ Latency (sliding window)
```

**EC2**: Generates traffic ONLY  
**VPS**: Serves requests + reports its own health

## Quick Start

### On VPS (System Under Test)

1. **Deploy the service**:
   ```bash
   chmod +x deploy.sh
   ./deploy.sh
   ```

2. **Verify it's running**:
   ```bash
   curl http://127.0.0.1:3000/metrics | jq
   ```

3. **Open firewall** (make port 3000 accessible from EC2)

4. **Monitor during tests** (keep these terminals open):
   
   Terminal 1 - System resources:
   ```bash
   docker stats hono-metrics
   # or
   htop
   ```
   
   Terminal 2 - App health (every 2s):
   ```bash
   watch -n 2 "curl -s http://127.0.0.1:3000/metrics | jq '.eventLoop, .latency, .network'"
   ```

### On AWS EC2 (Load Generator)

1. **Install dependencies**:
   ```bash
   sudo apt update
   sudo apt install -y wrk jq curl
   ```

2. **Copy the benchmark script** (`benchmark_auto_stop.sh`) to EC2

3. **Edit the script** - Replace `VPS_PUBLIC_IP` with your actual VPS IP:
   ```bash
   VPS_URL="http://YOUR_VPS_IP:3000"
   ```

4. **Run the load test**:
   ```bash
   chmod +x benchmark_auto_stop.sh
   ./benchmark_auto_stop.sh
   ```

5. The test will **automatically stop** when ELU ≥ 0.9

## Endpoints

### `GET /health`
Simple health check returning `ok`

### `GET /metrics`
Returns comprehensive metrics:

```json
{
  "cpu": {
    "cores": 4,
    "usagePercent": 62.41
  },
  "memory": {
    "totalMB": 8192,
    "usedMB": 4210,
    "freeMB": 3982,
    "usagePercent": 51.4
  },
  "eventLoop": {
    "lag": {
      "minMs": 0.3,
      "maxMs": 642.8,
      "meanMs": 71.2,
      "p95Ms": 198.4
    },
    "elu": {
      "utilization": 0.87,
      "activeMs": 26034,
      "idleMs": 3921
    },
    "overloaded": false,
    "threshold": 0.9
  },
  "latency": {
    "windowSeconds": 10,
    "requests": 8921,
    "p50Ms": 17,
    "p95Ms": 143,
    "p99Ms": 311,
    "histogram": {
      "<=5ms": 241,
      "<=10ms": 981,
      "<=20ms": 4320,
      "<=50ms": 2674,
      "<=100ms": 503,
      "<=200ms": 157,
      "<=500ms": 45,
      "<=1000ms": 0,
      ">1000ms": 0
    }
  },
  "network": {
    "rxMbps": 82.4,
    "txMbps": 79.1
  },
  "process": {
    "pid": 1,
    "rssMB": 48,
    "uptimeSec": 120
  },
  "timestamp": "2026-02-02T12:00:00.000Z"
}
```

## Configuration

Edit [index.ts](index.ts) to adjust:

```typescript
const WINDOW_SECONDS = 10              // Sliding window duration
const RESET_INTERVAL_SECONDS = 60      // Auto-reset interval (0 = disabled)
const ELU_STOP_THRESHOLD = 0.9         // Auto-stop threshold
```

## How to Determine Max RPM

The **safe max RPM** is the last concurrency level before auto-stop where:

| Signal | Threshold |
|--------|-----------|
| ELU | < 0.9 |
| eventLoop.lag.p95 | < 100ms |
| latency.p95 | Stable (not climbing) |
| CPU | < 95% sustained |
| Errors | = 0 |

**Formula**: `RPM = Requests/sec × 60`

## Development

### Local development:
```bash
npm install
npm run dev
```

### Build:
```bash
npm run build
npm start
```

### Docker build manually:
```bash
docker build -t hono-metrics .
docker run -p 3000:3000 -v /proc:/proc:ro hono-metrics
```

### Run with Docker Compose:
```bash
# Build and start the service
docker compose up -d

# View logs
docker compose logs -f

# Stop the service
docker compose down

# Rebuild and restart
docker compose up -d --build
```

Note: The [docker-compose.yml](docker-compose.yml) file includes:
- Automatic restart policy (`unless-stopped`)
- `/proc` volume mount for network metrics (Linux only)
- Optional resource limits (commented out by default)
- Production environment variables

## Files

- `index.ts` - Main application with all metrics logic
- `server.ts` - Server entry point
- `Dockerfile` - Container image definition
- `docker-compose.yml` - Orchestration config
- `deploy.sh` - One-command deployment script (VPS)
- `benchmark_auto_stop.sh` - Auto-stop load test script (EC2)
- `package.json` - Node.js dependencies
- `tsconfig.json` - TypeScript configuration

## Troubleshooting

**Network metrics showing `null`?**
- Only works on Linux
- Requires `/proc:/proc:ro` volume mount
- Check `docker-compose.yml` has the volume configured

**Port 3000 not accessible from EC2?**
- Check VPS firewall rules
- Check cloud provider security groups
- Test with: `curl http://VPS_IP:3000/health`

**Load test not stopping automatically?**
- Verify `jq` is installed on EC2: `sudo apt install jq`
- Check network connectivity between EC2 and VPS
- Manually check: `curl http://VPS_IP:3000/metrics | jq '.eventLoop.overloaded'`

## License

MIT
