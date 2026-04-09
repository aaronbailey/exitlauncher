import Foundation

struct CloudInitService {
    static func generateUserData(authKey: String, hostname: String) -> String {
        let script = """
        #cloud-config
        runcmd:
          - curl -fsSL https://tailscale.com/install.sh | sh
          - echo 'net.ipv4.ip_forward = 1' | tee -a /etc/sysctl.d/99-tailscale.conf
          - echo 'net.ipv6.conf.all.forwarding = 1' | tee -a /etc/sysctl.d/99-tailscale.conf
          - sysctl -p /etc/sysctl.d/99-tailscale.conf
          - tailscale up --authkey=\(authKey) --advertise-exit-node --hostname=\(hostname)
        """
        return script
    }

    static func generateBase64UserData(authKey: String, hostname: String) -> String {
        let script = generateUserData(authKey: authKey, hostname: hostname)
        return Data(script.utf8).base64EncodedString()
    }

    static func generateHostname(region: String) -> String {
        let random = String((0..<4).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! })
        return "exitnode-\(region)-\(random)"
    }
}
