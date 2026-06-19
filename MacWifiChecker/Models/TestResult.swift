import Foundation

struct TestResult: Identifiable {
    let id: String          // == bssid
    let bssid: String
    let ssid: String
    var startedAt: Date?
    var finishedAt: Date?

    // 11 テスト項目
    var assoc:  TestItemStatus = .pending
    var v4Addr: TestItemStatus = .pending
    var v4GW:   TestItemStatus = .pending
    var v4Net:  TestItemStatus = .pending
    var v4MTU:  TestItemStatus = .pending   // pass(detail: "1500") で MTU バイト数
    var v4DNS:  TestItemStatus = .pending
    var v6Addr: TestItemStatus = .pending
    var v6GW:   TestItemStatus = .pending
    var v6Net:  TestItemStatus = .pending
    var v6MTU:  TestItemStatus = .pending
    var v6DNS:  TestItemStatus = .pending

    // テスト中に取得したネットワーク情報（エクスポート用）
    var ipv4Address: String?
    var ipv4Gateway: String?
    var ipv4DNSServers: [String] = []
    var ipv6Address: String?
    var ipv6Gateway: String?
    var ipv6DNSServers: [String] = []

    init(bssid: String, ssid: String) {
        self.id = bssid
        self.bssid = bssid
        self.ssid = ssid
    }

    /// 全項目を .stopped に設定する（Stop ボタン押下時）
    mutating func markAllPendingAsStopped() {
        let items: [WritableKeyPath<TestResult, TestItemStatus>] = [
            \.assoc, \.v4Addr, \.v4GW, \.v4Net, \.v4MTU, \.v4DNS,
            \.v6Addr, \.v6GW, \.v6Net, \.v6MTU, \.v6DNS
        ]
        for kp in items {
            if case .pending = self[keyPath: kp] { self[keyPath: kp] = .stopped }
            if case .running = self[keyPath: kp] { self[keyPath: kp] = .stopped }
        }
    }
}
