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
   # Option A: View monitor service logs (easiest with docker-compose)
   docker compose logs -f monitor
   
   # Option B: Manual watch command
   watch -n 2 "curl -s http://127.0.0.1:3000/metrics | jq '.eventLoop, .latency, .network'"
   ```

### On AWS EC2 (Load Generator)

1. **Install dependencies**:
   ```bash
   sudo apt update
   sudo apt install -y wrk jq curl bc
   ```

2. **Copy the benchmark scripts** to EC2:
   - `benchmark_auto_stop.sh` - Basic benchmark
   - `benchmark_with_capture.sh` - Benchmark with automatic result capture
   - `compare_results.sh` - Compare results between VPS systems
   - `capture_results.sh` - Manual result capture

3. **Run load test with automatic result capture**:
   ```bash
   chmod +x benchmark_with_capture.sh
   ./benchmark_with_capture.sh <VPS_IP> <VPS_NAME>
   
   # Example:
   ./benchmark_with_capture.sh 192.168.1.100 aws-t3-medium
   ```

4. The test will **automatically stop** when ELU ≥ 0.9 and save results to `./results/`

## Performance Analysis & Comparison

### Capture Results

After running a load test, results are automatically saved to `./results/<VPS_NAME>_<TIMESTAMP>.json`

**Manual capture** (if needed):
```bash
./capture_results.sh <vps_name> <test_description>
# Example:
./capture_results.sh "digitalocean-basic" "8GB-4vCPU-test"
```

### Compare Two VPS Systems

```bash
./compare_results.sh results/vps1_*.json results/vps2_*.json
```

**Example output:**
```
====================================
 VPS Performance Comparison
====================================

VPS 1: aws-t3-medium (tested: 2026-02-02T10:30:00Z)
VPS 2: digitalocean-basic (tested: 2026-02-02T11:45:00Z)

====================================
 System Specifications
====================================
Metric               | VPS 1           | VPS 2          
--------------------------------------------------------------
CPU Cores            | 2               | 4              
Total Memory (MB)    | 4096            | 8192           

====================================
 Performance Metrics
====================================
Metric                    | VPS 1           | VPS 2           | Winner    
--------------------------------------------------------------------------------
CPU Usage %               | 45.2            | 38.7            | VPS 2     
Memory Usage %            | 52.1            | 28.3            | VPS 2     
ELU                       | 0.87            | 0.72            | VPS 2     
Event Loop Lag P95 (ms)   | 198.4           | 124.5           | VPS 2     
Latency P50 (ms)          | 17              | 12              | VPS 2     
Latency P95 (ms)          | 143             | 89              | VPS 2     
Latency P99 (ms)          | 311             | 187             | VPS 2     
Requests (10s window)     | 8921            | 12450           | VPS 2     
```

### Analyze Single Result

```bash
# View full results
cat results/vps_name_*.json | jq

# View specific metrics
cat results/vps_name_*.json | jq '.summary'
cat results/vps_name_*.json | jq '.test_results[] | {concurrency, requests_per_sec}'

# View system specs
cat results/vps_name_*.json | jq '.system'
```

### Key Metrics Explained

| Metric | What it means | Good Value |
|--------|---------------|------------|
| **Max RPS** | Maximum requests per second sustained | Higher is better |
| **Max RPM** | Maximum requests per minute (RPS × 60) | Higher is better |
| **Safe Concurrency** | Last stable concurrency level before overload | Your capacity limit |
| **ELU** | Event Loop Utilization - how busy the event loop is | < 0.85 is healthy |
| **Event Loop Lag P95** | 95th percentile event loop delay | < 100ms is good |
| **Latency P50/P95/P99** | Response time percentiles | Lower is better |
| **CPU Usage %** | CPU utilization during test | < 95% sustained |
| **Memory Usage %** | RAM utilization | < 90% recommended |

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
# Build and start the service (includes monitoring)
docker compose up -d

# View metrics service logs
docker compose logs -f metrics

# View live monitoring (recommended during load tests)
docker compose logs -f monitor

# View all logs
docker compose logs -f

# Stop all services
docker compose down

# Rebuild and restart
docker compose up -d --build
```

Note: The [docker-compose.yml](docker-compose.yml) file includes:
- **Main service** (`metrics`): The Hono.js performance metrics API
- **Monitor service** (`monitor`): Continuously polls `/metrics` every 2 seconds and displays results
- Automatic restart policy (`unless-stopped`)
- Production environment variables
- Optional resource limits (commented out by default)

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
