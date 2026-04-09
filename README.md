# ExitLauncher

A macOS menu bar app that spins up VPS instances as Tailscale exit nodes with one click. Pick a provider and region, launch a node, and route your traffic through it — all from your menu bar.

## Features

- **Multi-provider** — Launch exit nodes on Vultr, Digital Ocean, or Fly.io
- **One-click provisioning** — Select a region, click Launch, done in ~60-90 seconds
- **Auto-destroy timers** — Set nodes to self-destruct after 1, 4, or 24 hours to control costs
- **Instant exit node switching** — Click "Use" to route all traffic through the node via Tailscale
- **Favorite regions** — Star frequently used regions for quick access
- **Status at a glance** — Menu bar rocket icon changes color: white (offline), yellow (node ready), green (connected)
- **Live timers** — See uptime and countdown to auto-destroy on each node
- **Automatic route approval** — Exit node routes are auto-approved via the Tailscale API

## Install

### Download (no Xcode needed)

1. Download `ExitLauncher.zip` from the [latest release](https://github.com/aaronbailey/exitlauncher/releases/latest)
2. Unzip and drag `ExitLauncher.app` to your Applications folder
3. Right-click → **Open** on first launch (to bypass Gatekeeper)

### Requirements

- macOS 14.0+ (Sonoma or later)
- [Tailscale](https://apps.apple.com/us/app/tailscale/id1475387142?mt=12) (Mac App Store version)

### Build from source

```bash
brew install xcodegen
xcodegen generate
open ExitLauncher.xcodeproj
# Cmd+R to build and run
```

## Setup

### API Keys

Open the app from the menu bar and go to **Settings**. You need at least one provider key plus the two Tailscale keys:

**Providers (at least one):**

| Provider | Where to get the key |
|----------|---------------------|
| Vultr | [my.vultr.com/settings/#settingsapi](https://my.vultr.com/settings/#settingsapi) |
| Digital Ocean | [cloud.digitalocean.com/account/api/tokens](https://cloud.digitalocean.com/account/api/tokens) (scopes: droplet, region) |
| Fly.io | [fly.io dashboard](https://fly.io/dashboard) → Tokens (or `fly tokens create`) |

**Tailscale (required):**

| Key | Where to get it | What it does |
|-----|----------------|--------------|
| **Auth Key** | [login.tailscale.com/admin/settings/keys](https://login.tailscale.com/admin/settings/keys) | Lets new nodes join your tailnet (use a reusable key) |
| **API Key** | [login.tailscale.com/admin/settings/keys](https://login.tailscale.com/admin/settings/keys) | Auto-approves exit node routes on new nodes |

### Launch a node

Click the rocket icon → **Launch New Node** → pick a provider (if multiple configured) → pick a region → set a timer → **Launch**. The node provisions in ~60-90 seconds, then click **Use** to connect.

## How it works

1. Creates an instance on the selected provider:
   - **Vultr/DO**: VPS with cloud-init that installs Tailscale, enables IP forwarding, and joins your tailnet
   - **Fly.io**: Machine running the `tailscale/tailscale` Docker image with auth key via env vars
2. Polls until the instance is running, then polls the Tailscale API until the node appears in your tailnet
3. Auto-approves the exit node's advertised routes (`0.0.0.0/0` and `::/0`) via the Tailscale management API
4. Sets your Mac to use the node as an exit node via the Tailscale local HTTP API

## Cost

| Provider | Cheapest plan | Hourly cost | 4-hour session |
|----------|--------------|-------------|----------------|
| Vultr | vc2-1c-1gb | ~$0.007/hr | ~$0.03 |
| Digital Ocean | s-1vcpu-512mb-10gb | ~$0.006/hr | ~$0.02 |
| Fly.io | shared-1x-256mb | ~$0.003/hr | ~$0.01 |

Auto-destroy timers prevent forgotten instances from running up a bill.

## License

MIT
