import Foundation
import CoreWLAN
import CoreLocation

enum WiFiError: LocalizedError {
    case noInterface
    case locationDenied
    case networkNotFound(bssid: String)
    case associationFailed(underlying: Error)
    case bssidMismatch(expected: String, actual: String?)

    var errorDescription: String? {
        switch self {
        case .noInterface:               return "Wi-Fiインターフェースが見つかりません"
        case .locationDenied:            return "位置情報へのアクセスが許可されていません"
        case .networkNotFound(let b):    return "BSSID \(b) のネットワークが見つかりません（再スキャンが必要な場合があります）"
        case .associationFailed(let e):  return "接続失敗: \(e.localizedDescription)"
        case .bssidMismatch(let ex, let ac): return "BSSID不一致: 期待=\(ex) 実際=\(String(describing: ac))"
        }
    }
}

@MainActor
final class WiFiService: NSObject, ObservableObject {
    @Published var locationAuthStatus: CLAuthorizationStatus = .notDetermined

    private let client = CWWiFiClient.shared()
    private var networkCache: [String: CWNetwork] = [:]   // bssid(lower) -> CWNetwork
    private var isScanning = false
    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
        locationAuthStatus = locationManager.authorizationStatus
    }

    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    // MARK: - Scan

    /// 周囲の AP をスキャンして APInfo の配列を返す。
    /// ネットワークキャッシュを更新するため、associate の前に必ず呼ぶこと。
    func scan() async throws -> [APInfo] {
        guard let iface = client.interface() else { throw WiFiError.noInterface }
        guard !isScanning else { return [] }
        isScanning = true
        defer { isScanning = false }
        let networks: Set<CWNetwork> = try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try iface.scanForNetworks(withName: nil)
                    cont.resume(returning: result)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
        networkCache.removeAll()
        var aps: [APInfo] = []
        for net in networks {
            guard let bssid = net.bssid, !bssid.isEmpty else { continue }
            let key = bssid.lowercased()
            networkCache[key] = net
            aps.append(makeAPInfo(from: net))
        }
        return aps.sorted { $0.ssid == $1.ssid ? $0.bssid < $1.bssid : $0.ssid < $1.ssid }
    }

    // MARK: - Associate / Disassociate

    /// 指定 BSSID の AP に接続し、接続後の BSSID が一致することを確認する。
    func associate(bssid: String, psk: String) async throws {
        guard let iface = client.interface() else { throw WiFiError.noInterface }
        let key = bssid.lowercased()
        guard let network = networkCache[key] else { throw WiFiError.networkNotFound(bssid: bssid) }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try iface.associate(to: network, password: psk)
                    cont.resume()
                } catch {
                    cont.resume(throwing: WiFiError.associationFailed(underlying: error))
                }
            }
        }
        // 接続後の BSSID を検証
        let actual = iface.bssid()?.lowercased()
        guard actual == key else {
            throw WiFiError.bssidMismatch(expected: bssid, actual: actual)
        }
    }

    func disassociate() {
        client.interface()?.disassociate()
    }

    // MARK: - Helpers

    private func makeAPInfo(from net: CWNetwork) -> APInfo {
        // Callers must guard that bssid is non-nil and non-empty before calling this.
        let bssid = net.bssid!.lowercased()
        let band: String
        switch net.wlanChannel?.channelBand {
        case .band2GHz: band = "2.4GHz"
        case .band5GHz: band = "5GHz"
        case .band6GHz: band = "6GHz"
        default:        band = "Unknown"
        }
        return APInfo(id: bssid, ssid: net.ssid ?? "", bssid: bssid, band: band, rssi: net.rssiValue)
    }
}

extension WiFiService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.locationAuthStatus = manager.authorizationStatus
        }
    }
}
