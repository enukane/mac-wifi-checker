import Foundation
import SwiftUI

@Observable
@MainActor
final class AppViewModel {
    // MARK: - State

    var aps: [APInfo] = []
    var results: [String: TestResult] = [:]      // bssid -> TestResult
    var testStatus: TestStatus = .idle
    var config: AppConfig = AppConfig()
    var configFileURL: URL? = nil                // 最後に読み込んだ設定ファイルのパス
    var filterText: String = ""
    var errorMessage: String? = nil

    var filteredAPs: [APInfo] {
        guard !filterText.isEmpty else { return aps }
        let q = filterText.lowercased()
        return aps.filter { $0.ssid.lowercased().contains(q) || $0.bssid.lowercased().contains(q) }
    }

    var selectedAPs: [APInfo] { aps.filter { $0.isSelected } }

    var isRunning: Bool {
        if case .running = testStatus { return true }
        return false
    }

    // MARK: - Services

    private let wifiService: WiFiService
    private let networkTester: NetworkTestService
    private let configService = ConfigService()
    let exporter = ResultExporter()

    private var testTask: Task<Void, Never>?

    init(wifiService: WiFiService? = nil, networkTester: NetworkTestService = NetworkTestService()) {
        self.wifiService = wifiService ?? WiFiService()
        self.networkTester = networkTester
    }

    func requestLocationPermission() {
        wifiService.requestLocationPermission()
    }

    // MARK: - Scan

    func scan() async {
        errorMessage = nil
        do {
            var scanned = try await wifiService.scan()
            configService.applyAutoSelect(config: config, to: &scanned)
            aps = scanned
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Selection

    func toggleSelection(bssid: String) {
        guard let i = aps.firstIndex(where: { $0.bssid == bssid }) else { return }
        aps[i].isSelected.toggle()
    }

    func selectAll()  { for i in aps.indices { aps[i].isSelected = true } }
    func clearAll()   { for i in aps.indices { aps[i].isSelected = false } }

    func setPSKOverride(for bssid: String, psk: String?) {
        guard let i = aps.firstIndex(where: { $0.bssid == bssid }) else { return }
        aps[i].pskOverride = psk
    }

    // MARK: - Config Load / Save

    func loadConfig(from url: URL) {
        do {
            config = try configService.load(from: url)
            configFileURL = url
            // 既存 AP に auto_select を再適用
            configService.applyAutoSelect(config: config, to: &aps)
        } catch {
            errorMessage = "設定ファイルの読み込みに失敗しました: \(error.localizedDescription)"
        }
    }

    func saveConfig(to url: URL) {
        do {
            try configService.save(config, to: url)
            configFileURL = url
        } catch {
            errorMessage = "設定ファイルの保存に失敗しました: \(error.localizedDescription)"
        }
    }

    // MARK: - Test Execution

    func startTest() {
        guard !selectedAPs.isEmpty, !isRunning else { return }
        results.removeAll()
        testStatus = .idle

        testTask = Task {
            let targets = selectedAPs
            for ap in targets {
                guard !Task.isCancelled else { break }
                await runTestsForAP(ap)
            }
            if !Task.isCancelled {
                testStatus = .complete
            }
        }
    }

    func stopTest() {
        testTask?.cancel()
        testTask = nil
        // 未完了の結果を .stopped にする
        for bssid in results.keys {
            results[bssid]?.markAllPendingAsStopped()
        }
        testStatus = .stopped
    }

    private func runTestsForAP(_ ap: APInfo) async {
        let psk = ap.pskOverride ?? config.passphrase
        var result = TestResult(bssid: ap.bssid, ssid: ap.ssid)
        result.startedAt = Date()
        results[ap.bssid] = result
        var associated = false   // track whether association succeeded

        defer {
            results[ap.bssid]?.finishedAt = Date()
            if associated { wifiService.disassociate() }  // only disassociate if we actually connected
        }

        // --- Association ---
        testStatus = .running(bssid: ap.bssid, step: "Association")
        result.assoc = .running
        results[ap.bssid] = result
        do {
            try await wifiService.associate(bssid: ap.bssid, psk: psk)
            result.assoc = .pass()
            associated = true   // association succeeded; defer should disassociate
        } catch {
            result.assoc = .fail(detail: error.localizedDescription)
            result.v4Addr = .skip; result.v4GW  = .skip; result.v4Net = .skip
            result.v4MTU  = .skip; result.v4DNS  = .skip
            result.v6Addr = .skip; result.v6GW  = .skip; result.v6Net = .skip
            result.v6MTU  = .skip; result.v6DNS  = .skip
            results[ap.bssid] = result
            return
        }
        results[ap.bssid] = result

        // --- IPv4 ---
        await runIPv4Tests(ap: ap, result: &result)
        results[ap.bssid] = result

        // --- IPv6 ---
        await runIPv6Tests(ap: ap, result: &result)
        results[ap.bssid] = result
    }

    private func runIPv4Tests(ap: APInfo, result: inout TestResult) async {
        // v4 Addr
        testStatus = .running(bssid: ap.bssid, step: "IPv4 DHCP")
        result.v4Addr = .running
        results[ap.bssid] = result
        guard let info = try? await networkTester.testV4Addr(result: &result) else {
            result.v4Addr = result.v4Addr.isTerminal ? result.v4Addr : .fail(detail: "DHCPタイムアウト")
            result.v4GW = .skip; result.v4Net = .skip; result.v4MTU = .skip; result.v4DNS = .skip
            return
        }
        results[ap.bssid] = result

        // v4 GW
        testStatus = .running(bssid: ap.bssid, step: "IPv4 GW ping")
        result.v4GW = .running; results[ap.bssid] = result
        await networkTester.testV4GW(result: &result, gateway: info.gateway)
        results[ap.bssid] = result
        guard case .pass = result.v4GW else {
            result.v4Net = .skip; result.v4MTU = .skip; result.v4DNS = .skip
            return
        }

        // v4 Net
        testStatus = .running(bssid: ap.bssid, step: "IPv4 Internet ping")
        result.v4Net = .running; results[ap.bssid] = result
        await networkTester.testV4Net(result: &result, target: config.ipv4PingTarget)
        results[ap.bssid] = result

        // v4 MTU（GW が届けば実施）
        testStatus = .running(bssid: ap.bssid, step: "IPv4 MTU")
        result.v4MTU = .running; results[ap.bssid] = result
        await networkTester.testV4MTU(result: &result, gateway: info.gateway)
        results[ap.bssid] = result

        // v4 DNS
        testStatus = .running(bssid: ap.bssid, step: "IPv4 DNS")
        result.v4DNS = .running; results[ap.bssid] = result
        if let dns = info.dnsServers.first {
            await networkTester.testV4DNS(result: &result, server: dns, target: config.dnsLookupTarget)
        } else {
            result.v4DNS = .fail(detail: "DNSサーバー未取得")
        }
        results[ap.bssid] = result
    }

    private func runIPv6Tests(ap: APInfo, result: inout TestResult) async {
        // v6 Addr
        testStatus = .running(bssid: ap.bssid, step: "IPv6 RA/SLAAC")
        result.v6Addr = .running; results[ap.bssid] = result
        guard let info = try? await networkTester.testV6Addr(result: &result) else {
            result.v6Addr = result.v6Addr.isTerminal ? result.v6Addr : .fail(detail: "RAタイムアウト")
            result.v6GW = .skip; result.v6Net = .skip; result.v6MTU = .skip; result.v6DNS = .skip
            return
        }
        results[ap.bssid] = result

        // v6 GW
        testStatus = .running(bssid: ap.bssid, step: "IPv6 GW ping")
        result.v6GW = .running; results[ap.bssid] = result
        await networkTester.testV6GW(result: &result, gateway: info.gateway)
        results[ap.bssid] = result
        guard case .pass = result.v6GW else {
            result.v6Net = .skip; result.v6MTU = .skip; result.v6DNS = .skip
            return
        }

        // v6 Net
        testStatus = .running(bssid: ap.bssid, step: "IPv6 Internet ping")
        result.v6Net = .running; results[ap.bssid] = result
        await networkTester.testV6Net(result: &result, target: config.ipv6PingTarget)
        results[ap.bssid] = result

        // v6 MTU
        testStatus = .running(bssid: ap.bssid, step: "IPv6 MTU")
        result.v6MTU = .running; results[ap.bssid] = result
        await networkTester.testV6MTU(result: &result, gateway: info.gateway)
        results[ap.bssid] = result

        // v6 DNS
        testStatus = .running(bssid: ap.bssid, step: "IPv6 DNS")
        result.v6DNS = .running; results[ap.bssid] = result
        if let dns = info.dnsServers.first {
            await networkTester.testV6DNS(result: &result, server: dns, target: config.dnsLookupTarget)
        } else {
            result.v6DNS = .fail(detail: "IPv6 DNSサーバー未取得")
        }
        results[ap.bssid] = result
    }

    // MARK: - Export

    func exportResults(format: ExportFormat, to url: URL) {
        let sorted = results.values.sorted { $0.ssid == $1.ssid ? $0.bssid < $1.bssid : $0.ssid < $1.ssid }
        do {
            let data = try exporter.export(sorted, format: format)
            try data.write(to: url, options: .atomic)
        } catch {
            errorMessage = "エクスポート失敗: \(error.localizedDescription)"
        }
    }
}
