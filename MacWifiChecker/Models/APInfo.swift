import Foundation

struct APInfo: Identifiable, Hashable {
    let id: String          // == bssid（小文字正規化済み）
    let ssid: String
    let bssid: String       // 小文字、コロン区切り例: "aa:bb:cc:dd:ee:01"
    let band: String        // "2.4GHz" / "5GHz" / "6GHz" / "Unknown"
    let rssi: Int           // dBm（負値）
    var isSelected: Bool = false
    var pskOverride: String? = nil
    var fromConfig: Bool = false    // Config の auto_select でチェックされた場合 true

    init(id: String, ssid: String, bssid: String, band: String, rssi: Int) {
        self.id = id
        self.ssid = ssid
        self.bssid = bssid
        self.band = band
        self.rssi = rssi
    }

    func hash(into hasher: inout Hasher) { hasher.combine(bssid) }
    static func == (lhs: APInfo, rhs: APInfo) -> Bool { lhs.bssid == rhs.bssid }
}
