# ExitLauncher

A macOS menu bar app that spins up VPS instances as Tailscale exit nodes with one click. Pick a provider and region, launch a node, and route your traffic through it — all from your menu bar.

## Features

- **Multi-provider** — Launch exit nodes on Vultr, Digital Ocean, Fly.io, or AWS
- **One-click provisioning** — Select a region, click Launch, done in ~60-90 seconds
- **Auto-destroy timers** — Set nodes to self-destruct after 1, 4, or 24 hours to control costs
- **Instant exit node switching** — Click "Use" to route all traffic through the node via Tailscale
- **Favorite regions** — Star frequently used regions for quick access
- **Unified region list** — All providers shown in one list, grouped by continent, with color-coded provider badges
- **Status at a glance** — Menu bar rocket icon changes color: white (offline), yellow (node ready), green (connected)
- **Live timers** — See uptime and countdown to auto-destroy on each node
- **Automatic route approval** — Exit node routes are auto-approved via the Tailscale API
- **Auto-cleanup** — Destroyed nodes are automatically removed from your Tailscale device list

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

Open the app from the menu bar rocket icon and go to **Settings**. You need at least one provider key plus two Tailscale keys.

### Provider keys (at least one)

#### Vultr
1. Go to [my.vultr.com/settings/#settingsapi](https://my.vultr.com/settings/#settingsapi)
2. Click **Enable API** if not already enabled
3. Copy the API key
4. Paste into the **Vultr API Key** field in Settings

#### Digital Ocean
1. Go to [cloud.digitalocean.com/account/api/tokens](https://cloud.digitalocean.com/account/api/tokens)
2. Click **Generate New Token**
3. Name it (e.g. "ExitLauncher"), select **Custom Scopes**
4. Enable: **Droplet** (full access) and **Region** (read)
5. Click **Generate Token** and copy it
6. Paste into the **Digital Ocean API Key** field in Settings

#### Fly.io
1. Install the Fly CLI: `brew install flyctl`
2. Authenticate: `fly auth login`
3. Create a token: `fly tokens create deploy -a exitlauncher` (or any name — the app auto-creates it)
4. Copy the token (starts with `FlyV1 ...`)
5. Paste into the **Fly.io API Token** field in Settings

#### AWS
1. Go to [console.aws.amazon.com](https://console.aws.amazon.com) → search **IAM** → **Users** → **Create user**
2. Name it (e.g. "exitlauncher"), click **Next**
3. Click **Attach policies directly**, search for **AmazonEC2FullAccess**, check it, click **Next** → **Create user**
4. Click the user → **Security credentials** → **Create access key**
5. Select **Third-party service**, confirm, click **Create access key**
6. Copy both values and enter in Settings as: `ACCESS_KEY_ID:SECRET_ACCESS_KEY` (joined with a colon)
7. **Important**: Copy the secret key immediately — AWS only shows it once

> **Note on AWS regions**: ExitLauncher lists 16 default-enabled AWS regions. Some regions (Cape Town, Bahrain, Hong Kong, Jakarta, etc.) are "opt-in" and disabled by default. To enable them, go to [AWS Account Settings](https://console.aws.amazon.com/billing/home#/account) → **AWS Regions** → click **Enable** next to the region you want.

### Tailscale keys (required)

Both keys are created at [login.tailscale.com/admin/settings/keys](https://login.tailscale.com/admin/settings/keys):

#### Auth Key
1. Click **Generate auth key**
2. Check **Reusable** (so multiple nodes can use the same key)
3. Check **Ephemeral** (so nodes auto-remove when they go offline)
4. Click **Generate key** and copy it (starts with `tskey-auth-...`)
5. Paste into the **Tailscale Auth Key** field in Settings

#### API Key
1. Click **Generate API key** (different section from auth keys)
2. Copy it (starts with `tskey-api-...`)
3. Paste into the **Tailscale API Key** field in Settings

This key is used to auto-approve exit node routes and clean up devices when you destroy nodes.

### Launch a node

Click the rocket icon → **Launch New Node** → pick a region → set a timer → **Launch**. The node provisions in ~60-90 seconds, then click **Use** to connect.

## How it works

1. Creates an instance on the selected provider:
   - **Vultr**: VPS with base64-encoded cloud-init
   - **Digital Ocean**: Droplet with plain-text cloud-init
   - **AWS**: EC2 instance (t3.nano) with base64-encoded cloud-init
   - **Fly.io**: Machine running `tailscale/tailscale` Docker image with env vars
2. Polls until the instance is running, then waits for the node to appear in your tailnet with advertised routes
3. Auto-approves the exit node routes (`0.0.0.0/0` and `::/0`) via the Tailscale management API
4. Sets your Mac to use the node as an exit node via the Tailscale local HTTP API
5. On destroy, terminates the instance and removes the device from your Tailscale device list

## Cost

| Provider | Instance type | Hourly cost | 4-hour session |
|----------|--------------|-------------|----------------|
| Vultr | vc2-1c-1gb | ~$0.007/hr | ~$0.03 |
| Digital Ocean | s-1vcpu-512mb-10gb | ~$0.006/hr | ~$0.02 |
| AWS | t3.nano | ~$0.005/hr | ~$0.02 |
| Fly.io | shared-1x-256mb | ~$0.003/hr | ~$0.01 |

Auto-destroy timers prevent forgotten instances from running up a bill.

## License

Copyright 2026 Aaron Bailey. All rights reserved.
