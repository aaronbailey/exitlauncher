import Foundation
import Combine

@MainActor
class InstanceManager: ObservableObject {
    @Published var instances: [VPSInstance] = []
    @Published var isLaunching = false
    @Published var currentExitNode: String? = nil
    @Published var lastError: String?

    let vultr = VultrAPI()
    let digitalOcean = DigitalOceanAPI()
    let flyio = FlyioAPI()
    let aws = AWSAPI()
    let tailscaleAPI = TailscaleAPI()
    private let store = InstanceStore()
    private var destroyTimer: Timer?

    // MARK: - Lifecycle

    func loadState() async {
        instances = await store.load()
        for i in instances.indices where instances[i].status == .provisioning {
            pollUntilReady(instanceId: instances[i].id, provider: instances[i].provider)
        }
        startDestroyTimer()
        await refreshTailscaleStatus()
    }

    // MARK: - Region Loading

    func loadRegions(for provider: Provider) async throws -> [Region] {
        switch provider {
        case .vultr:
            return try await vultr.listRegions()
        case .digitalOcean:
            return try await digitalOcean.listRegions()
        case .flyio:
            return await flyio.listRegions()
        case .aws:
            return await aws.listRegions()
        }
    }

    // MARK: - Launch

    func launchNode(region: Region, destroyAfter: TimeInterval?) async {
        guard let authKey = KeychainService.read(key: .tailscaleAuthKey), !authKey.isEmpty else {
            lastError = "Tailscale auth key not configured. Add it in Settings."
            return
        }

        isLaunching = true
        lastError = nil

        let hostname = CloudInitService.generateHostname(region: region.slug)

        do {
            var instance: VPSInstance

            switch region.provider {
            case .vultr:
                let userData = CloudInitService.generateBase64UserData(authKey: authKey, hostname: hostname)
                instance = try await vultr.createInstance(
                    region: region.slug, plan: "vc2-1c-1gb", userData: userData, label: hostname
                )
            case .digitalOcean:
                let userData = CloudInitService.generateUserData(authKey: authKey, hostname: hostname)
                instance = try await digitalOcean.createInstance(
                    region: region.slug, userData: userData, label: hostname
                )
            case .flyio:
                instance = try await flyio.createMachine(
                    region: region.slug, authKey: authKey, hostname: hostname
                )
            case .aws:
                let userData = CloudInitService.generateBase64UserData(authKey: authKey, hostname: hostname)
                instance = try await aws.createInstance(
                    region: region.slug, userData: userData, label: hostname
                )
            }

            instance = VPSInstance(
                id: instance.id,
                provider: region.provider,
                region: region.slug,
                regionName: region.displayName,
                tailscaleHostname: hostname,
                ipAddress: instance.ipAddress,
                createdAt: Date(),
                destroyAt: destroyAfter.map { Date().addingTimeInterval($0) },
                status: .provisioning
            )
            instances.append(instance)
            await store.save(instances)

            pollUntilReady(instanceId: instance.id, provider: region.provider)
        } catch {
            lastError = error.localizedDescription
        }

        isLaunching = false
    }

    // MARK: - Polling

    private func pollUntilReady(instanceId: String, provider: Provider) {
        Task {
            // Phase 1: Wait for instance to be active
            var providerReady = false
            for _ in 0..<60 {
                try? await Task.sleep(nanoseconds: 5_000_000_000)

                guard let index = instances.firstIndex(where: { $0.id == instanceId }) else { return }

                do {
                    let isReady: Bool
                    switch provider {
                    case .vultr:
                        let detail = try await vultr.getInstance(id: instanceId)
                        isReady = detail.status == "active" && detail.powerStatus == "running" && detail.serverStatus == "ok"
                        if isReady && (instances[index].ipAddress.isEmpty || instances[index].ipAddress == "0.0.0.0") {
                            instances[index].ipAddress = detail.mainIp
                        }
                    case .digitalOcean:
                        let detail = try await digitalOcean.getInstance(id: instanceId)
                        isReady = detail.status == "active"
                        if isReady, let ip = detail.networks?.v4?.first(where: { $0.type == "public" })?.ipAddress {
                            instances[index].ipAddress = ip
                        }
                    case .flyio:
                        let machine = try await flyio.getMachine(id: instanceId)
                        isReady = machine.state == "started"
                    case .aws:
                        let region = instances[index].region
                        let result = try await aws.getInstance(region: region, id: instanceId)
                        isReady = result.status == "running"
                        if isReady && !result.ip.isEmpty {
                            instances[index].ipAddress = result.ip
                        }
                    }

                    if isReady {
                        await store.save(instances)
                        providerReady = true
                        break
                    }
                } catch {
                    // Continue polling on transient errors
                }
            }

            guard providerReady else {
                if let index = instances.firstIndex(where: { $0.id == instanceId }) {
                    instances[index].status = .error
                    lastError = "Instance failed to start"
                    await store.save(instances)
                }
                return
            }

            // Phase 2: Wait for node to appear in Tailscale and approve exit node route
            guard let index = instances.firstIndex(where: { $0.id == instanceId }) else { return }
            let hostname = instances[index].tailscaleHostname

            for _ in 0..<36 {
                try? await Task.sleep(nanoseconds: 5_000_000_000)

                do {
                    try await tailscaleAPI.approveExitNode(hostname: hostname)
                    if let idx = instances.firstIndex(where: { $0.id == instanceId }) {
                        instances[idx].status = .ready
                        await store.save(instances)
                    }
                    return
                } catch TailscaleAPIError.deviceNotFound {
                    continue
                } catch TailscaleAPIError.noAPIKey {
                    if let idx = instances.firstIndex(where: { $0.id == instanceId }) {
                        instances[idx].status = .ready
                        lastError = "Node is up but exit node route needs manual approval (no Tailscale API key configured)"
                        await store.save(instances)
                    }
                    return
                } catch {
                    continue
                }
            }

            if let idx = instances.firstIndex(where: { $0.id == instanceId }) {
                instances[idx].status = .ready
                lastError = "Node is up but may not have joined Tailscale yet"
                await store.save(instances)
            }
        }
    }

    // MARK: - Destroy

    func destroyNode(_ instance: VPSInstance) async {
        guard let index = instances.firstIndex(where: { $0.id == instance.id }) else { return }
        instances[index].status = .destroying
        lastError = nil

        if currentExitNode == instance.tailscaleHostname {
            try? await TailscaleService.clearExitNode()
            currentExitNode = nil
        }

        do {
            switch instance.provider {
            case .vultr:
                try await vultr.deleteInstance(id: instance.id)
            case .digitalOcean:
                try await digitalOcean.deleteInstance(id: instance.id)
            case .flyio:
                try await flyio.deleteMachine(id: instance.id)
            case .aws:
                try await aws.deleteInstance(region: instance.region, id: instance.id)
            }
            instances.removeAll { $0.id == instance.id }
            await store.save(instances)

            // Remove from Tailscale device list
            try? await tailscaleAPI.removeDevice(hostname: instance.tailscaleHostname)
        } catch {
            lastError = error.localizedDescription
            if let idx = instances.firstIndex(where: { $0.id == instance.id }) {
                instances[idx].status = .error
            }
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
        } catch {}
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
        let expired = instances.filter { inst in
            guard let destroyAt = inst.destroyAt else { return false }
            return destroyAt <= now && inst.status != .destroying
        }
        for instance in expired {
            await destroyNode(instance)
        }
    }
}
