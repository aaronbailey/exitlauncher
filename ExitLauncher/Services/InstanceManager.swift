import Foundation
import Combine

@MainActor
class InstanceManager: ObservableObject {
    @Published var instances: [VPSInstance] = []
    @Published var isLaunching = false
    @Published var currentExitNode: String? = nil // tailscale hostname
    @Published var lastError: String?

    let vultr = VultrAPI()
    let tailscaleAPI = TailscaleAPI()
    private let store = InstanceStore()
    private var destroyTimer: Timer?

    // MARK: - Lifecycle

    func loadState() async {
        instances = await store.load()
        // Refresh status of provisioning instances
        for i in instances.indices where instances[i].status == .provisioning {
            await pollInstanceStatus(id: instances[i].id, index: i)
        }
        startDestroyTimer()
        await refreshTailscaleStatus()
    }

    // MARK: - Launch

    func launchNode(region: Region, destroyAfter: TimeInterval?) async {
        guard let authKey = KeychainService.read(key: .tailscaleAuthKey), !authKey.isEmpty else {
            lastError = "Tailscale auth key not configured. Add it in Settings."
            return
        }

        isLaunching = true
        lastError = nil

        let hostname = CloudInitService.generateHostname(region: region.id)
        let userData = CloudInitService.generateBase64UserData(authKey: authKey, hostname: hostname)
        let plan = "vc2-1c-1gb"

        do {
            var instance = try await vultr.createInstance(
                region: region.id,
                plan: plan,
                userData: userData,
                label: hostname
            )
            instance = VPSInstance(
                id: instance.id,
                region: region.id,
                regionName: region.displayName,
                tailscaleHostname: hostname,
                ipAddress: instance.ipAddress,
                createdAt: Date(),
                destroyAt: destroyAfter.map { Date().addingTimeInterval($0) },
                status: .provisioning
            )
            instances.append(instance)
            await store.save(instances)

            // Start polling for readiness
            pollUntilReady(instanceId: instance.id)
        } catch {
            lastError = error.localizedDescription
        }

        isLaunching = false
    }

    // MARK: - Polling

    private func pollUntilReady(instanceId: String) {
        Task {
            // Phase 1: Wait for Vultr instance to be active
            var vultrReady = false
            for _ in 0..<60 { // poll for up to 5 minutes
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds

                guard let index = instances.firstIndex(where: { $0.id == instanceId }) else { return }

                do {
                    let detail = try await vultr.getInstance(id: instanceId)

                    if detail.status == "active" && detail.powerStatus == "running" && detail.serverStatus == "ok" {
                        if instances[index].ipAddress.isEmpty || instances[index].ipAddress == "0.0.0.0" {
                            instances[index].ipAddress = detail.mainIp
                        }
                        await store.save(instances)
                        vultrReady = true
                        break
                    }
                } catch {
                    // Continue polling on transient errors
                }
            }

            guard vultrReady else {
                if let index = instances.firstIndex(where: { $0.id == instanceId }) {
                    instances[index].status = .error
                    lastError = "VPS failed to start"
                    await store.save(instances)
                }
                return
            }

            // Phase 2: Wait for node to appear in Tailscale and approve exit node route
            guard let index = instances.firstIndex(where: { $0.id == instanceId }) else { return }
            let hostname = instances[index].tailscaleHostname

            for _ in 0..<36 { // poll for up to 3 more minutes
                try? await Task.sleep(nanoseconds: 5_000_000_000)

                do {
                    try await tailscaleAPI.approveExitNode(hostname: hostname)
                    // Success — node found and routes approved
                    if let idx = instances.firstIndex(where: { $0.id == instanceId }) {
                        instances[idx].status = .ready
                        await store.save(instances)
                    }
                    return
                } catch TailscaleAPIError.deviceNotFound {
                    // Node hasn't joined tailnet yet, keep polling
                    continue
                } catch TailscaleAPIError.noAPIKey {
                    // No API key configured — mark ready anyway, user can approve manually
                    if let idx = instances.firstIndex(where: { $0.id == instanceId }) {
                        instances[idx].status = .ready
                        lastError = "Node is up but exit node route needs manual approval (no Tailscale API key configured)"
                        await store.save(instances)
                    }
                    return
                } catch {
                    // Other error — keep trying
                    continue
                }
            }

            // Timeout waiting for Tailscale — mark ready but warn
            if let idx = instances.firstIndex(where: { $0.id == instanceId }) {
                instances[idx].status = .ready
                lastError = "Node is up but may not have joined Tailscale yet"
                await store.save(instances)
            }
        }
    }

    private func pollInstanceStatus(id: String, index: Int) async {
        do {
            let detail = try await vultr.getInstance(id: id)
            if detail.status == "active" && detail.powerStatus == "running" && detail.serverStatus == "ok" {
                instances[index].status = .ready
                if instances[index].ipAddress.isEmpty || instances[index].ipAddress == "0.0.0.0" {
                    instances[index].ipAddress = detail.mainIp
                }
            }
        } catch {
            instances[index].status = .error
        }
        await store.save(instances)
    }

    // MARK: - Destroy

    func destroyNode(_ instance: VPSInstance) async {
        guard let index = instances.firstIndex(where: { $0.id == instance.id }) else { return }
        instances[index].status = .destroying
        lastError = nil

        // If this was our exit node, disconnect first
        if currentExitNode == instance.tailscaleHostname {
            try? await TailscaleService.clearExitNode()
            currentExitNode = nil
        }

        do {
            try await vultr.deleteInstance(id: instance.id)
            instances.removeAll { $0.id == instance.id }
            await store.save(instances)
        } catch {
            lastError = error.localizedDescription
            instances[index].status = .error
        }
    }

    // MARK: - Exit Node

    func useAsExitNode(_ instance: VPSInstance) async {
        lastError = nil
        do {
            try await TailscaleService.setExitNode(hostname: instance.tailscaleHostname)
            currentExitNode = instance.tailscaleHostname
        } catch {
            lastError = error.localizedDescription
        }
    }

    func disconnectExitNode() async {
        do {
            try await TailscaleService.clearExitNode()
            currentExitNode = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshTailscaleStatus() async {
        do {
            let status = try await TailscaleService.status()
            currentExitNode = status.currentExitNode?.hostName
        } catch {
            // Tailscale might not be running — that's okay
        }
    }

    // MARK: - Auto-Destroy Timer

    private func startDestroyTimer() {
        destroyTimer?.invalidate()
        destroyTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkAutoDestroy()
            }
        }
    }

    private func checkAutoDestroy() async {
        let now = Date()
        let expiredInstances = instances.filter { instance in
            guard let destroyAt = instance.destroyAt else { return false }
            return destroyAt <= now && instance.status != .destroying
        }

        for instance in expiredInstances {
            await destroyNode(instance)
        }
    }
}
