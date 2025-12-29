# Darkstar
> **Backend-less Internet Health & Flux Monitoring**

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Zig](https://img.shields.io/badge/Zig-0.14.1-orange.svg)

**Darkstar** is a terminal-based CLI tool that empowers network engineers to monitor internet routing stability (BGP) and outage signals directly from their local machine. By connecting directly to public telemetry streams (like RIPE RIS Live) via secure TLS, it provides a real-time "Pulse" of the internet without relying on proprietary SaaS backends.

![Screenshot Placeholder](https://via.placeholder.com/800x400?text=Darkstar+TUI+Dashboard)

## 🚀 Features

- **Real-Time BGP Stream**: Connects securely to `ris-live.ripe.net` to stream global routing table updates (Announcements/Withdrawals).
- **Flux Analysis**: Computes an instantaneous "Health Score" for any ASN or Prefix based on update volatility.
- **Interactive TUI**: A zero-dependency, high-performance terminal dashboard with live scrolling logs, rate counters, and drift timers.
- **Secure by Default**: Static TLS implementation (via BearSSL) ensures telemetry integrity.
- **Single Binary**: No Python envs, no Node modules, just one fast binary.

## 📦 Installation

### Prerequisites
- [Zig 0.14.1](https://ziglang.org/download/) or newer.

### Build from Source
```bash
# Clone the repository
git clone https://github.com/copyleftdev/darkstar.git
cd darkstar

# Build in ReleaseSafe mode
zig build -Doptimize=ReleaseSafe
```
The binary will be available at `./zig-out/bin/darkstar`.

## 🛠 Usage

### Check Network Health
Monitor an Autonomous System (ASN) or IP Prefix for stability:
```bash
darkstar health 3333
# or
darkstar health 1.1.1.0/24
```
This launches the interactive dashboard.
- Press `q` to quit.

### View Global Events
(Coming Soon)
```bash
darkstar events
```

### Active Probing
(Coming Soon)
```bash
darkstar probe ping 8.8.8.8
```

## 🏗 Architecture

Darkstar inverts the typical monitoring model. Instead of a server collecting data and a client viewing it, **Darkstar IS the collector**.

1.  **Ingest**: Connects via WSS (Secure WebSockets) to RIPE RIS Live nodes.
2.  **Normalize**: Buffers high-volume BGP updates, deduplicates signals, and aggregates "Flap" events.
3.  **Visualise**: Renders 60FPS ANSI updates to the terminal.

## 🤝 Contributing

We welcome contributions! Please check the `implementation_plan.md` (if available) or open an issue.

## 📄 License

MIT © Darkstar Team
