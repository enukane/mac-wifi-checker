import Foundation

final class ConfigService {
    func load(from url: URL) throws -> AppConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AppConfig.self, from: data)
    }

    func save(_ config: AppConfig, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: url, options: .atomic)
    }

    /// config の auto_select ルールを aps に適用する。
    /// ssids/bssids のいずれかにマッチした AP を isSelected = true / fromConfig = true にする。
    /// PSK オーバーライドも適用する。
    func applyAutoSelect(config: AppConfig, to aps: inout [APInfo]) {
        let configBSSIDs = Set(config.autoSelect.bssids.map { $0.lowercased() })
        let configSSIDs  = Set(config.autoSelect.ssids)

        for i in aps.indices {
            if configSSIDs.contains(aps[i].ssid) || configBSSIDs.contains(aps[i].bssid.lowercased()) {
                aps[i].isSelected = true
                aps[i].fromConfig = true
            }
            if let psk = config.ssidPskOverrides[aps[i].ssid] {
                aps[i].pskOverride = psk
            }
        }
    }
}
