import Foundation

struct AppConfig: Equatable {
    var passphrase: String = ""
    var ipv4PingTarget: String = "1.1.1.1"
    var ipv6PingTarget: String = "2606:4700:4700::1111"
    var dnsLookupTarget: String = "www.google.com"
    var autoSelect: AutoSelectConfig = AutoSelectConfig()
    var ssidPskOverrides: [String: String] = [:]

    struct AutoSelectConfig: Equatable {
        var ssids: [String] = []
        var bssids: [String] = []
    }
}

extension AppConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case passphrase
        case ipv4PingTarget = "ipv4_ping_target"
        case ipv6PingTarget = "ipv6_ping_target"
        case dnsLookupTarget = "dns_lookup_target"
        case autoSelect = "auto_select"
        case ssidPskOverrides = "ssid_psk_overrides"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        passphrase     = try c.decodeIfPresent(String.self, forKey: .passphrase)     ?? ""
        ipv4PingTarget = try c.decodeIfPresent(String.self, forKey: .ipv4PingTarget) ?? "1.1.1.1"
        ipv6PingTarget = try c.decodeIfPresent(String.self, forKey: .ipv6PingTarget) ?? "2606:4700:4700::1111"
        dnsLookupTarget = try c.decodeIfPresent(String.self, forKey: .dnsLookupTarget) ?? "www.google.com"
        autoSelect     = try c.decodeIfPresent(AutoSelectConfig.self, forKey: .autoSelect) ?? AutoSelectConfig()
        ssidPskOverrides = try c.decodeIfPresent([String: String].self, forKey: .ssidPskOverrides) ?? [:]
    }
}

extension AppConfig.AutoSelectConfig: Codable {
    enum CodingKeys: String, CodingKey { case ssids, bssids }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ssids  = try c.decodeIfPresent([String].self, forKey: .ssids)  ?? []
        bssids = try c.decodeIfPresent([String].self, forKey: .bssids) ?? []
    }
}
