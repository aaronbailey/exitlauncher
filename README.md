# ExitLauncher

A macOS menu bar app that spins up Vultr VPS instances as Tailscale exit nodes with one click. Pick a region, launch a node, and route your traffic through it — all from your menu bar.

## Features

- **One-click VPS provisioning** — Launch a Vultr instance in any region as a Tailscale exit node
- **Auto-destroy timers** — Set nodes to self-destruct after 1, 4, or 24 hours to control costs
- **Instant exit node switching** — Click "Use" to route all traffic through the node via Tailscale
- **Favorite regions** — Star frequently used regions for quick access
- **Status at a glance** — Menu bar icon changes color: white (offline), yellow (node ready), green (connected)
- **Automatic route approval** — Exit node routes are auto-approved via the Tailscale API

## Requirements

- macOS 14.0+
- [Tailscale](https://apps.apple.com/us/app/tailscale/id1475387142?mt=12) (Mac App Store version)
- [Xcode](https://apps.apple.com/us/app/xcode/id497799835?mt=12) (to build)
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Setup

### 1. Build

```bash
xcodegen generate
open ExitLauncher.xcodeproj
# Cmd+R to build and run
```

### 2. API Keys

Open the app from the menu bar and go to **Settings**. You need three keys:

| Key | Where to get it | What it does |
|-----|----------------|--------------|
| **Vultr API Key** | [my.vultr.com/settings/#settingsapi](https://my.vultr.com/settings/#settingsapi) | Creates and destroys VPS instances |
| **Tailscale Auth Key** | [login.tailscale.com/admin/settings/keys](https://login.tailscale.com/admin/settings/keys) | Lets new VPS nodes join your tailnet (use a reusable key) |
| **Tailscale API Key** | [login.tailscale.com/admin/settings/keys](https://login.tailscale.com/admin/settings/keys) | Auto-approves exit node routes on new nodes |

### 3. Launch a node

Click the rocket icon → **Launch New Node** → pick a region → set a timer → **Launch**. The node provisions in ~60-90 seconds, then click **Use** to connect.

## How it works

1. Creates a Vultr VPS with a [cloud-init](https://tailscale.com/docs/install/with-cloud-init) script that installs Tailscale, enables IP forwarding, and joins your tailnet as an exit node
2. Polls Vultr until the instance is running, then polls the Tailscale API until the node appears in your tailnet
3. Auto-approves the exit node's advertised routes (`0.0.0.0/0` and `::/0`) via the Tailscale management API
4. Sets your Mac to use the node as an exit node via the Tailscale local HTTP API

## Cost

Vultr's cheapest plan (`vc2-1c-1gb`) costs ~$0.007/hour. A 4-hour session costs about $0.03. Auto-destroy timers prevent forgotten instances from running up a bill.

## License

MIT
