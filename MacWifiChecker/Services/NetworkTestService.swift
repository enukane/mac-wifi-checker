import Foundation

enum ShellError: Error {
    case failed(exitCode: Int32, output: String)
    case cancelled
}

final class NetworkTestService {
    private let wifiInterface: String

    init(wifiInterface: String = "en0") {
        self.wifiInterface = wifiInterface
    }

    // MARK: - Shell Runner

    /// コマンドを実行して標準出力を返す。終了コード != 0 は ShellError.failed を throw。
    nonisolated func run(_ args: [String]) async throws -> String {
        try await runWithTimeout(seconds: .infinity, args)
    }

    /// タイムアウト付きでコマンドを実行する。
    /// timeout(1) コマンドに依存せず Swift の構造化並行処理でタイムアウトを実現する。
    /// macOS アプリの PATH には /opt/homebrew/bin が含まれないため外部 timeout は使用不可。
    nonisolated func runWithTimeout(seconds: Double, _ args: [String]) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await self._run(args) }
            if seconds.isFinite {
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    throw ShellError.cancelled
                }
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    nonisolated private func _run(_ args: [String]) async throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = args
        let outPipe = Pipe(), errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError  = errPipe

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                proc.terminationHandler = { p in
                    let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    if p.terminationStatus == 0 {
                        cont.resume(returning: out)
                    } else {
                        cont.resume(throwing: ShellError.failed(exitCode: p.terminationStatus,
                                                                 output: (out + err).trimmingCharacters(in: .whitespacesAndNewlines)))
                    }
                }
                do { try proc.run() } catch { cont.resume(throwing: error) }
            }
        } onCancel: {
            // proc.isRunning が false の場合（未起動 or 既終了）は terminate() を呼ばない
            if proc.isRunning { proc.terminate() }
        }
    }

    // MARK: - DHCP / RA ポーリング

    struct IPv4Info {
        let address: String
        let gateway: String
        let dnsServers: [String]
    }

    struct IPv6Info {
        let address: String       // グローバルスコープ
        let gateway: String
        let dnsServers: [String]
    }

    /// DHCP で IPv4 アドレスが取得されるまでポーリングする（最大 timeoutSeconds 秒）
    nonisolated func waitForIPv4(timeoutSeconds: Double = 15) async throws -> IPv4Info {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            try Task.checkCancellation()
            if let info = try? await fetchIPv4Info() { return info }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        throw ShellError.failed(exitCode: 1, output: "DHCPタイムアウト: \(timeoutSeconds)秒以内にIPv4アドレスが取得できませんでした")
    }

    /// RA/SLAAC で IPv6 グローバルアドレスが取得されるまでポーリングする（最大 timeoutSeconds 秒）
    nonisolated func waitForIPv6(timeoutSeconds: Double = 20) async throws -> IPv6Info {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            try Task.checkCancellation()
            if let info = try? await fetchIPv6Info() { return info }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        throw ShellError.failed(exitCode: 1, output: "RAタイムアウト: \(timeoutSeconds)秒以内にIPv6グローバルアドレスが取得できませんでした")
    }

    private func fetchIPv4Info() async throws -> IPv4Info? {
        // ipconfig getpacket en0 で DHCP パケット情報を取得
        let output = try await run(["ipconfig", "getpacket", wifiInterface])
        guard let addr = parseIPConfigValue(output, key: "yiaddr"),
              !addr.isEmpty, addr != "0.0.0.0" else { return nil }
        let gw  = parseIPConfigMulti(output, key: "router") ?? ""
        let dns = parseIPConfigMultiList(output, key: "domain_name_server")
        return IPv4Info(address: addr, gateway: gw, dnsServers: dns)
    }

    private func fetchIPv6Info() async throws -> IPv6Info? {
        let ifOutput = try await run(["ifconfig", wifiInterface])
        // inet6 アドレスのうちグローバルスコープ（fe80:: 以外）を抽出
        let lines = ifOutput.components(separatedBy: "\n")
        let globalV6 = lines.first {
            $0.contains("inet6") && !$0.contains("fe80") && !$0.contains("::1")
        }.flatMap { line -> String? in
            let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
            return parts.dropFirst().first
        }
        guard let addr = globalV6 else { return nil }

        // デフォルト IPv6 ゲートウェイ
        let routeOutput = (try? await run(["route", "-n", "get", "-inet6", "default"])) ?? ""
        let gw = routeOutput.components(separatedBy: "\n")
            .first { $0.contains("gateway:") }
            .map {
                $0.components(separatedBy: ":")
                  .dropFirst()
                  .joined(separator: ":")
                  .trimmingCharacters(in: .whitespaces)
            }
            ?? ""

        // DNS（scutil --dns からインターフェース固有のサーバーを取得）
        let scutilOut = (try? await run(["scutil", "--dns"])) ?? ""
        let dnsServers = parseScutilIPv6DNS(scutilOut)

        return IPv6Info(address: addr, gateway: gw, dnsServers: dnsServers)
    }

    // MARK: - 11 テスト項目

    /// テスト 1: Association（WiFiService.associate で完了済み）→ TestResult に記録するだけ
    nonisolated func testAssoc(result: inout TestResult, expectedBSSID: String) {
        // association 成功は呼び出し側（AppViewModel）が保証済み
        result.assoc = .pass()
    }

    /// テスト 2: IPv4 DHCP アドレス取得
    nonisolated func testV4Addr(result: inout TestResult) async throws -> IPv4Info {
        let info = try await waitForIPv4()
        result.v4Addr = .pass(detail: info.address)
        result.ipv4Address   = info.address
        result.ipv4Gateway   = info.gateway
        result.ipv4DNSServers = info.dnsServers
        return info
    }

    /// テスト 3: IPv4 デフォルトゲートウェイへの ping
    /// macOS ping の -I はマルチキャスト専用。ユニキャストの送信元バインドは -S <アドレス> を使う。
    nonisolated func testV4GW(result: inout TestResult, gateway: String, sourceAddress: String) async {
        do {
            _ = try await run(["ping", "-c1", "-W3000", "-S", sourceAddress, gateway])
            result.v4GW = .pass()
        } catch {
            result.v4GW = .fail(detail: "ping失敗: \(gateway)")
        }
    }

    /// テスト 4: IPv4 インターネット疎通
    nonisolated func testV4Net(result: inout TestResult, target: String, sourceAddress: String) async {
        do {
            _ = try await run(["ping", "-c1", "-W5000", "-S", sourceAddress, target])
            result.v4Net = .pass()
        } catch {
            result.v4Net = .fail(detail: "ping失敗: \(target)")
        }
    }

    /// テスト 5: IPv4 MTU（DF ビットを立てて二分探索）
    nonisolated func testV4MTU(result: inout TestResult, gateway: String, sourceAddress: String) async {
        let mtu = await binarySearchMTU(target: gateway, sourceAddress: sourceAddress, lo: 100, hi: 1472)
        if mtu > 0 {
            result.v4MTU = .pass(detail: "\(mtu + 28)")  // IP(20) + ICMP(8) + payload = MTU
        } else {
            result.v4MTU = .fail(detail: "MTU検出失敗")
        }
    }

    /// テスト 6: IPv4 DNS 解決
    nonisolated func testV4DNS(result: inout TestResult, server: String, target: String) async {
        guard !server.isEmpty else {
            result.v4DNS = .fail(detail: "DNSサーバーが取得できませんでした")
            return
        }
        do {
            _ = try await run(["dig", "@\(server)", target, "A", "+time=5", "+tries=1"])
            result.v4DNS = .pass()
        } catch {
            result.v4DNS = .fail(detail: "dig失敗: @\(server) \(target)")
        }
    }

    /// テスト 7: IPv6 アドレス取得（RA/SLAAC）
    nonisolated func testV6Addr(result: inout TestResult) async throws -> IPv6Info {
        let info = try await waitForIPv6()
        result.v6Addr = .pass(detail: info.address)
        result.ipv6Address    = info.address
        result.ipv6Gateway    = info.gateway
        result.ipv6DNSServers = info.dnsServers
        return info
    }

    /// テスト 8: IPv6 ゲートウェイへの ping6
    /// macOS ping6 は -W を数値タイムアウトとして受け付けない。
    /// timeout コマンドは macOS 非標準のため runWithTimeout で Swift レベルのタイムアウトを実現。
    nonisolated func testV6GW(result: inout TestResult, gateway: String) async {
        do {
            _ = try await runWithTimeout(seconds: 5, ["ping6", "-c1", "-I", wifiInterface, gateway])
            result.v6GW = .pass()
        } catch {
            result.v6GW = .fail(detail: "ping6失敗: \(gateway)")
        }
    }

    /// テスト 9: IPv6 インターネット疎通
    nonisolated func testV6Net(result: inout TestResult, target: String) async {
        do {
            _ = try await runWithTimeout(seconds: 5, ["ping6", "-c1", "-I", wifiInterface, target])
            result.v6Net = .pass()
        } catch {
            result.v6Net = .fail(detail: "ping6失敗: \(target)")
        }
    }

    /// テスト 10: IPv6 リンク MTU
    /// v6GW / v6Net テストで既にトラフィックが発生済み（PMTUD が働く前提）のため、
    /// その後に ifconfig でリンク MTU を読む。L2TP 等のトンネルがある場合は
    /// ルーターが RA MTU オプションでインターフェース MTU を通知するためここに反映される。
    nonisolated func testV6MTU(result: inout TestResult) async {
        do {
            let output = try await run(["ifconfig", wifiInterface])
            let tokens = output.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            if let idx = tokens.firstIndex(of: "mtu"),
               idx + 1 < tokens.count,
               let mtu = Int(tokens[idx + 1]) {
                result.v6MTU = .pass(detail: "\(mtu)")
            } else {
                result.v6MTU = .fail(detail: "MTU解析失敗")
            }
        } catch {
            result.v6MTU = .fail(detail: "ifconfig失敗")
        }
    }

    /// テスト 11: IPv6 DNS 解決
    nonisolated func testV6DNS(result: inout TestResult, server: String, target: String) async {
        guard !server.isEmpty else {
            result.v6DNS = .fail(detail: "DNSサーバーが取得できませんでした")
            return
        }
        do {
            _ = try await run(["dig", "@\(server)", target, "AAAA", "+time=5", "+tries=1"])
            result.v6DNS = .pass()
        } catch {
            result.v6DNS = .fail(detail: "dig失敗: @\(server) \(target)")
        }
    }

    // MARK: - IPv4 MTU 二分探索

    /// 指定範囲でペイロードサイズを二分探索して、通る最大ペイロードバイト数を返す（IPv4 のみ）。
    private func binarySearchMTU(target: String, sourceAddress: String, lo: Int, hi: Int) async -> Int {
        var lo = lo, hi = hi, best = 0
        while lo <= hi {
            let mid = (lo + hi) / 2
            let ok = await pingOnce(target: target, sourceAddress: sourceAddress, payloadSize: mid)
            if ok { best = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return best
    }

    private func pingOnce(target: String, sourceAddress: String, payloadSize: Int) async -> Bool {
        do {
            _ = try await run(["ping", "-c1", "-W2000", "-D", "-S", sourceAddress, "-s\(payloadSize)", target])
            return true
        } catch { return false }
    }

    // MARK: - ipconfig パーサー

    private func parseIPConfigValue(_ output: String, key: String) -> String? {
        // 例: "yiaddr = 192.168.1.10"
        let pattern = "\(key) = ([\\d\\.]+)"
        guard let range = output.range(of: pattern, options: .regularExpression) else { return nil }
        return output[range].components(separatedBy: " = ").last
    }

    private func parseIPConfigMulti(_ output: String, key: String) -> String? {
        // 例: "router (ip_mult): {192.168.1.1}"
        let pattern = "\(key) \\([^)]+\\): \\{([^}]+)\\}"
        guard let match = output.range(of: pattern, options: .regularExpression) else { return nil }
        let inner = output[match]
        return inner.components(separatedBy: "{").last?.components(separatedBy: "}").first?
                    .components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces)
    }

    private func parseIPConfigMultiList(_ output: String, key: String) -> [String] {
        let pattern = "\(key) \\([^)]+\\): \\{([^}]+)\\}"
        guard let match = output.range(of: pattern, options: .regularExpression) else { return [] }
        let inner = output[match]
        guard let list = inner.components(separatedBy: "{").last?.components(separatedBy: "}").first else { return [] }
        return list.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func parseScutilIPv6DNS(_ output: String) -> [String] {
        // nameserver[N] : 2001:db8::1 のような行を抽出
        output.components(separatedBy: "\n")
            .filter { $0.contains("nameserver") && $0.contains(":") }
            .compactMap { $0.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces) }
            .filter { $0.contains(":") }   // IPv6 アドレスはコロンを含む
    }
}
