import Foundation

actor InstanceStore {
    private let fileURL: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = .prettyPrinted
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("ExitLauncher", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.fileURL = appDir.appendingPathComponent("instances.json")
    }

    func load() -> [VPSInstance] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? decoder.decode([VPSInstance].self, from: data)) ?? []
    }

    func save(_ instances: [VPSInstance]) {
        guard let data = try? encoder.encode(instances) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
