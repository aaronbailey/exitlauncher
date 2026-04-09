# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
# Generate Xcode project (required after adding/removing .swift files)
xcodegen generate

# Build
xcodebuild -project ExitLauncher.xcodeproj -scheme ExitLauncher -configuration Debug build

# Run
open ~/Library/Developer/Xcode/DerivedData/ExitLauncher-*/Build/Products/Debug/ExitLauncher.app
# Or use Cmd+R in Xcode after: open ExitLauncher.xcodeproj
```

Xcodegen regenerates `Info.plist` and clears `ExitLauncher.entitlements` — after running `xcodegen generate`, restore the entitlements `com.apple.security.network.client` key.

## Architecture

**ExitLauncher** is a macOS menu bar app (LSUIElement) that provisions Vultr VPS instances as Tailscale exit nodes. It uses `NSStatusBar` + `NSPopover` (not `MenuBarExtra`, which fails to render on macOS 26).

### Core flow
1. User picks a Vultr region → `InstanceManager.launchNode()` calls `VultrAPI.createInstance()` with cloud-init user data that installs Tailscale
2. Two-phase polling: waits for Vultr VPS active, then waits for node to appear in tailnet and auto-approves exit node routes via `TailscaleAPI`
3. User clicks "Use" → `TailscaleService.setExitNode()` patches local Tailscale prefs to route traffic through the node
4. Auto-destroy timer checks every 30s for expired instances

### Key services
- **VultrAPI** (actor) — REST client for Vultr v2 API. User data must be base64-encoded.
- **TailscaleService** — Talks to the Tailscale Mac App Store local HTTP API at `127.0.0.1:{port}`. Auth discovered via `lsof -c IPNExtension` parsing the sameuserproof filename.
- **TailscaleAPI** (actor) — Tailscale management API (api.tailscale.com) for approving exit node routes on new devices.
- **InstanceManager** (@MainActor ObservableObject) — Central orchestrator connecting all services, owns published state.
- **KeychainService** — File-based secrets at `~/Library/Application Support/ExitLauncher/secrets.json` (not actual Keychain — avoids repeated password prompts for unsigned apps).

### Tailscale local API quirks
- The Mac App Store Tailscale CLI binary crashes with `BundleIdentifiers.swift: Fatal error` — always use the local HTTP API instead.
- Setting exit node requires masked prefs format: `{"ExitNodeIDSet": true, "ExitNodeID": "..."}`. Without the `Set` flag, PATCH to `/localapi/v0/prefs` silently does nothing.
- Auth uses Basic auth with empty username and password from the sameuserproof filename.

### Navigation
Views use a `PopoverScreen` enum for in-popover navigation (main → launch / settings) with callback-based dismissal — no sheets or separate windows.

## Three API keys required
- **Vultr API Key** — provisions VPS instances
- **Tailscale Auth Key** (`tskey-auth-...`) — injected into cloud-init for VPS to join tailnet
- **Tailscale API Key** (`tskey-api-...`) — auto-approves exit node routes after VPS joins
