# Mac Wi-Fi Checker 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 展示会会場でWi-Fi APをBSSID指定で順番にテストし、IPv4/IPv6の疎通・MTU・DNSを11項目×AP数のマトリックス形式で表示するmacOS GUIアプリを構築する。

**Architecture:** SwiftUI（macOS 14+）＋ CoreWLAN（BSSID指定接続）＋ SystemConfiguration（DHCP/RA情報）＋ サブプロセス（ping/dig）のハイブリッド構成。`@Observable` AppViewModelが全状態を管理し、Services層（WiFiService / NetworkTestService / ConfigService）が非同期処理を担う。

**Tech Stack:** Swift 5.9+, SwiftUI (macOS 14+), CoreWLAN, CoreLocation, SystemConfiguration, XCTest, xcodegen

---

## ファイル構成

```
MacWifiChecker/                          ← Xcode プロジェクトルート
├── project.yml                          ← xcodegen 定義
├── .gitignore
├── MacWifiChecker/                      ← アプリターゲット
│   ├── App/
│   │   └── MacWifiCheckerApp.swift      ← エントリポイント、AppViewModel注入
│   ├── Models/
│   │   ├── APInfo.swift                 ← SSID/BSSID/Band/RSSI/isSelected/pskOverride/fromConfig
│   │   ├── TestResult.swift             ← 11項目の TestItemStatus + 取得したIP情報
│   │   ├── AppConfig.swift              ← Codable: PSK/ping先/auto_select/psk_overrides
│   │   └── TestStatus.swift             ← enum: idle/running(bssid:step:)/stopped/complete
│   ├── Services/
│   │   ├── WiFiService.swift            ← CoreWLAN: scan/associate/disassociate + CWNetworkキャッシュ
│   │   ├── NetworkTestService.swift     ← ShellRunner + 11テスト + DHCP/RAポーリング
│   │   └── ConfigService.swift          ← JSON load/save/applyAutoSelect
│   ├── ViewModels/
│   │   └── AppViewModel.swift           ← @Observable: スキャン・テスト・Stop・Export 制御
│   ├── Views/
│   │   ├── ContentView.swift            ← VSplitView（上段/下段）+ ツールバー
│   │   ├── APListView.swift             ← List + Toggle + フィルタ + cfg バッジ
│   │   ├── SettingsView.swift           ← PSK/ping先/Start/Export
│   │   └── ResultMatrixView.swift       ← ScrollView（縦+横）+ 11列テーブル
│   ├── Utilities/
│   │   └── ResultExporter.swift         ← CSV/JSON エクスポート
│   ├── MacWifiChecker.entitlements
│   ├── Info.plist
│   └── Assets.xcassets/
└── MacWifiCheckerTests/
    ├── ConfigServiceTests.swift
    └── ResultExporterTests.swift
```

---

## Task 1: Xcode プロジェクトのスキャフォールド

**Files:**
- Create: `project.yml`
- Create: `.gitignore`
- Create: `MacWifiChecker/MacWifiChecker.entitlements`
- Create: `MacWifiChecker/Assets.xcassets/Contents.json`

- [ ] **Step 1: xcodegen をインストール**

```bash
brew install xcodegen
```

期待出力: `xcodegen` コマンドが使えること (`xcodegen --version`)

- [ ] **Step 2: `project.yml` を作成**

`/Users/n_kane/Dev/shownet/2026/mac-wifi-checker/project.yml` に以下を書く:

```yaml
name: MacWifiChecker
options:
  bundleIdPrefix: net.shownet
  deploymentTarget:
    macOS: "14.0"
  createIntermediateGroups: true
targets:
  MacWifiChecker:
    type: application
    platform: macOS
    sources:
      - path: MacWifiChecker
        createIntermediateGroups: true
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: net.shownet.MacWifiChecker
        MACOSX_DEPLOYMENT_TARGET: "14.0"
        SWIFT_VERSION: "5.9"
        CODE_SIGN_ENTITLEMENTS: MacWifiChecker/MacWifiChecker.entitlements
        ENABLE_HARDENED_RUNTIME: YES
        CODE_SIGN_IDENTITY: "-"
    info:
      path: MacWifiChecker/Info.plist
      properties:
        CFBundleName: "Mac Wi-Fi Checker"
        CFBundleDisplayName: "Mac Wi-Fi Checker"
        NSLocationWhenInUseUsageDescription: "Wi-Fi AP の SSID/BSSID を取得するために位置情報へのアクセスが必要です。"
        NSHumanReadableCopyright: ""
  MacWifiCheckerTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: MacWifiCheckerTests
        createIntermediateGroups: true
    settings:
      base:
        MACOSX_DEPLOYMENT_TARGET: "14.0"
    dependencies:
      - target: MacWifiChecker
```

- [ ] **Step 3: エンタイトルメントファイルを作成**

`MacWifiChecker/MacWifiChecker.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.networking.wifi-info</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 4: Assets.xcassets を作成**

```bash
mkdir -p MacWifiChecker/Assets.xcassets
```

`MacWifiChecker/Assets.xcassets/Contents.json`:

```json
{
  "info" : { "author" : "xcode", "version" : 1 }
}
```

- [ ] **Step 5: .gitignore を作成**

`.gitignore`:

```
.DS_Store
*.xcuserstate
xcuserdata/
DerivedData/
.build/
.superpowers/
MacWifiChecker.xcodeproj/project.xcworkspace/xcshareddata/
```

- [ ] **Step 6: xcodegen でプロジェクトを生成**

```bash
cd /Users/n_kane/Dev/shownet/2026/mac-wifi-checker
xcodegen generate
```

期待出力: `MacWifiChecker.xcodeproj` が生成される。

- [ ] **Step 7: ビルド確認（空でOK）**

`MacWifiChecker/App/MacWifiCheckerApp.swift` を作成:

```swift
import SwiftUI

@main
struct MacWifiCheckerApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Loading...")
        }
    }
}
```

```bash
xcodebuild build -scheme MacWifiChecker -destination 'platform=macOS' 2>&1 | tail -5
```

期待: `** BUILD SUCCEEDED **`

- [ ] **Step 8: git init & 初回コミット**

```bash
cd /Users/n_kane/Dev/shownet/2026/mac-wifi-checker
git init
git add .
git commit -m "chore: scaffold Xcode project with xcodegen"
```

---

## Task 2: データモデル

**Files:**
- Create: `MacWifiChecker/Models/APInfo.swift`
- Create: `MacWifiChecker/Models/TestResult.swift`
- Create: `MacWifiChecker/Models/AppConfig.swift`
- Create: `MacWifiChecker/Models/TestStatus.swift`

- [ ] **Step 1: `APInfo.swift` を作成**

```swift
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
```

- [ ] **Step 2: `TestStatus.swift` を作成**

```swift
import Foundation

enum TestItemStatus: Equatable {
    case pending
    case running
    case pass(detail: String? = nil)
    case fail(detail: String? = nil)
    case skip
    case stopped

    var isTerminal: Bool {
        switch self {
        case .pass, .fail, .skip, .stopped: return true
        default: return false
        }
    }

    var displayText: String {
        switch self {
        case .pending:            return "—"
        case .running:            return "…"
        case .pass(let d):        return d ?? "✓"
        case .fail(let d):        return d.map { "✗ \($0)" } ?? "✗"
        case .skip:               return "—"
        case .stopped:            return "■"
        }
    }
}

enum TestStatus: Equatable {
    case idle
    case running(bssid: String, step: String)
    case stopped
    case complete
}
```

- [ ] **Step 3: `TestResult.swift` を作成**

```swift
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
```

- [ ] **Step 4: `AppConfig.swift` を作成**

```swift
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
```

- [ ] **Step 5: ビルド確認**

```bash
xcodebuild build -scheme MacWifiChecker -destination 'platform=macOS' 2>&1 | tail -3
```

期待: `** BUILD SUCCEEDED **`

- [ ] **Step 6: コミット**

```bash
git add MacWifiChecker/Models/
git commit -m "feat: add data models (APInfo, TestResult, AppConfig, TestStatus)"
```

---

## Task 3: ConfigService (TDD)

**Files:**
- Create: `MacWifiChecker/Services/ConfigService.swift`
- Create: `MacWifiCheckerTests/ConfigServiceTests.swift`

- [ ] **Step 1: テストファイルを作成（失敗するテストを書く）**

`MacWifiCheckerTests/ConfigServiceTests.swift`:

```swift
import XCTest
@testable import MacWifiChecker

final class ConfigServiceTests: XCTestCase {
    var sut: ConfigService!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        sut = ConfigService()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - load

    func test_load_fullJSON_returnsCorrectConfig() throws {
        let json = """
        {
          "passphrase": "testpass",
          "ipv4_ping_target": "8.8.8.8",
          "ipv6_ping_target": "2001:4860:4860::8888",
          "dns_lookup_target": "example.com",
          "auto_select": { "ssids": ["mynet"], "bssids": ["aa:bb:cc:dd:ee:01"] },
          "ssid_psk_overrides": { "staff": "staffpw" }
        }
        """
        let url = tempDir.appendingPathComponent("config.json")
        try json.data(using: .utf8)!.write(to: url)

        let config = try sut.load(from: url)

        XCTAssertEqual(config.passphrase, "testpass")
        XCTAssertEqual(config.ipv4PingTarget, "8.8.8.8")
        XCTAssertEqual(config.ipv6PingTarget, "2001:4860:4860::8888")
        XCTAssertEqual(config.dnsLookupTarget, "example.com")
        XCTAssertEqual(config.autoSelect.ssids, ["mynet"])
        XCTAssertEqual(config.autoSelect.bssids, ["aa:bb:cc:dd:ee:01"])
        XCTAssertEqual(config.ssidPskOverrides, ["staff": "staffpw"])
    }

    func test_load_missingOptionalFields_usesDefaults() throws {
        let json = """
        { "passphrase": "x", "auto_select": { "ssids": [], "bssids": [] } }
        """
        let url = tempDir.appendingPathComponent("min.json")
        try json.data(using: .utf8)!.write(to: url)

        let config = try sut.load(from: url)

        XCTAssertEqual(config.ipv4PingTarget, "1.1.1.1")
        XCTAssertEqual(config.ipv6PingTarget, "2606:4700:4700::1111")
        XCTAssertEqual(config.dnsLookupTarget, "www.google.com")
        XCTAssertEqual(config.ssidPskOverrides, [:])
    }

    func test_load_invalidJSON_throws() {
        let url = tempDir.appendingPathComponent("bad.json")
        try! "not json".data(using: .utf8)!.write(to: url)
        XCTAssertThrowsError(try sut.load(from: url))
    }

    // MARK: - save & load round-trip

    func test_saveAndLoad_roundTrip() throws {
        var original = AppConfig()
        original.passphrase = "hello"
        original.autoSelect.ssids = ["shownet"]
        original.ssidPskOverrides = ["vip": "vippass"]
        let url = tempDir.appendingPathComponent("rt.json")

        try sut.save(original, to: url)
        let loaded = try sut.load(from: url)

        XCTAssertEqual(original, loaded)
    }

    // MARK: - applyAutoSelect

    func test_applyAutoSelect_ssidMatch_selectsAllBSSIDs() {
        var aps = [
            makeAP(ssid: "shownet", bssid: "aa:bb:cc:dd:ee:01"),
            makeAP(ssid: "shownet", bssid: "aa:bb:cc:dd:ee:02"),
            makeAP(ssid: "other",   bssid: "ff:ee:dd:cc:bb:01"),
        ]
        var config = AppConfig()
        config.autoSelect.ssids = ["shownet"]

        sut.applyAutoSelect(config: config, to: &aps)

        XCTAssertTrue(aps[0].isSelected)
        XCTAssertTrue(aps[0].fromConfig)
        XCTAssertTrue(aps[1].isSelected)
        XCTAssertFalse(aps[2].isSelected)
    }

    func test_applyAutoSelect_bssidMatch_selectsOnlyThatBSSID() {
        var aps = [
            makeAP(ssid: "shownet", bssid: "aa:bb:cc:dd:ee:01"),
            makeAP(ssid: "shownet", bssid: "aa:bb:cc:dd:ee:02"),
        ]
        var config = AppConfig()
        config.autoSelect.bssids = ["aa:bb:cc:dd:ee:01"]

        sut.applyAutoSelect(config: config, to: &aps)

        XCTAssertTrue(aps[0].isSelected)
        XCTAssertFalse(aps[1].isSelected)
    }

    func test_applyAutoSelect_bssidCaseInsensitive() {
        var aps = [makeAP(ssid: "net", bssid: "aa:bb:cc:dd:ee:01")]
        var config = AppConfig()
        config.autoSelect.bssids = ["AA:BB:CC:DD:EE:01"]   // 大文字で指定

        sut.applyAutoSelect(config: config, to: &aps)

        XCTAssertTrue(aps[0].isSelected)
    }

    func test_applyAutoSelect_pskOverride_appliedToMatchingSSID() {
        var aps = [makeAP(ssid: "staff-net", bssid: "aa:bb:cc:dd:ee:01")]
        var config = AppConfig()
        config.ssidPskOverrides = ["staff-net": "staffpass"]

        sut.applyAutoSelect(config: config, to: &aps)

        XCTAssertEqual(aps[0].pskOverride, "staffpass")
    }

    // MARK: - helpers

    private func makeAP(ssid: String, bssid: String) -> APInfo {
        APInfo(id: bssid, ssid: ssid, bssid: bssid, band: "5GHz", rssi: -60)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

```bash
xcodebuild test -scheme MacWifiChecker -destination 'platform=macOS' \
  -only-testing:MacWifiCheckerTests/ConfigServiceTests 2>&1 | grep -E "FAIL|error:"
```

期待: `ConfigService` が存在しないためビルドエラーになること。

- [ ] **Step 3: `ConfigService.swift` を実装**

`MacWifiChecker/Services/ConfigService.swift`:

```swift
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
```

- [ ] **Step 4: テストがパスすることを確認**

```bash
xcodebuild test -scheme MacWifiChecker -destination 'platform=macOS' \
  -only-testing:MacWifiCheckerTests/ConfigServiceTests 2>&1 | grep -E "TEST SUITE|PASS|FAIL"
```

期待: 全テスト PASS。

- [ ] **Step 5: コミット**

```bash
git add MacWifiChecker/Services/ConfigService.swift MacWifiCheckerTests/ConfigServiceTests.swift
git commit -m "feat: add ConfigService with JSON load/save/applyAutoSelect (TDD)"
```

---

## Task 4: ResultExporter (TDD)

**Files:**
- Create: `MacWifiChecker/Utilities/ResultExporter.swift`
- Create: `MacWifiCheckerTests/ResultExporterTests.swift`

- [ ] **Step 1: テストを書く**

`MacWifiCheckerTests/ResultExporterTests.swift`:

```swift
import XCTest
@testable import MacWifiChecker

final class ResultExporterTests: XCTestCase {
    var sut: ResultExporter!

    override func setUp() {
        super.setUp()
        sut = ResultExporter()
    }

    // MARK: - CSV

    func test_exportCSV_headerPresent() throws {
        let data = try sut.export([], format: .csv)
        let text = String(data: data, encoding: .utf8)!
        XCTAssertTrue(text.hasPrefix("timestamp,ssid,bssid,assoc,"))
    }

    func test_exportCSV_singlePassResult() throws {
        var result = makePassResult()
        result.v4MTU = .pass(detail: "1500")
        result.v6MTU = .pass(detail: "1500")

        let data = try sut.export([result], format: .csv)
        let lines = String(data: data, encoding: .utf8)!
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }

        XCTAssertEqual(lines.count, 2)  // header + 1 row
        XCTAssertTrue(lines[1].contains("aa:bb:cc:dd:ee:01"))
        XCTAssertTrue(lines[1].contains(",pass,"))
        XCTAssertTrue(lines[1].contains(",1500,"))
    }

    func test_exportCSV_failAndSkip() throws {
        var result = makeResult(bssid: "aa:bb:cc:dd:ee:02")
        result.assoc  = .pass()
        result.v4Addr = .fail(detail: "timeout")
        result.v4GW   = .skip

        let data = try sut.export([result], format: .csv)
        let text = String(data: data, encoding: .utf8)!
        XCTAssertTrue(text.contains(",fail,"))
        XCTAssertTrue(text.contains(",skip,"))
    }

    func test_exportCSV_ssidWithComma_escapedCorrectly() throws {
        var result = makeResult(bssid: "aa:bb:cc:dd:ee:03")
        result = TestResult(bssid: "aa:bb:cc:dd:ee:03", ssid: "net,work")
        result.assoc = .pass()

        let data = try sut.export([result], format: .csv)
        let text = String(data: data, encoding: .utf8)!
        XCTAssertTrue(text.contains("\"net,work\""))
    }

    // MARK: - JSON

    func test_exportJSON_validJSONWithResults() throws {
        let result = makePassResult()
        let data = try sut.export([result], format: .json)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertNotNil(json["exported_at"])
        let results = json["results"] as! [[String: Any]]
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0]["bssid"] as? String, "aa:bb:cc:dd:ee:01")
        XCTAssertEqual(results[0]["assoc"] as? String, "pass")
    }

    func test_exportJSON_mtuDetail() throws {
        var result = makePassResult()
        result.v4MTU = .pass(detail: "1472")

        let data = try sut.export([result], format: .json)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let results = json["results"] as! [[String: Any]]
        XCTAssertEqual(results[0]["v4_mtu"] as? String, "1472")
    }

    // MARK: - helpers

    private func makePassResult() -> TestResult {
        var r = makeResult(bssid: "aa:bb:cc:dd:ee:01")
        r.assoc  = .pass()
        r.v4Addr = .pass()
        r.v4GW   = .pass()
        r.v4Net  = .pass()
        r.v4MTU  = .pass(detail: "1500")
        r.v4DNS  = .pass()
        r.v6Addr = .pass()
        r.v6GW   = .pass()
        r.v6Net  = .pass()
        r.v6MTU  = .pass(detail: "1500")
        r.v6DNS  = .pass()
        return r
    }

    private func makeResult(bssid: String) -> TestResult {
        TestResult(bssid: bssid, ssid: "shownet")
    }
}
```

- [ ] **Step 2: テストが失敗することを確認（ビルドエラー）**

```bash
xcodebuild test -scheme MacWifiChecker -destination 'platform=macOS' \
  -only-testing:MacWifiCheckerTests/ResultExporterTests 2>&1 | grep "error:" | head -3
```

- [ ] **Step 3: `ResultExporter.swift` を実装**

`MacWifiChecker/Utilities/ResultExporter.swift`:

```swift
import Foundation

enum ExportFormat { case csv, json }

final class ResultExporter {
    func export(_ results: [TestResult], format: ExportFormat) throws -> Data {
        switch format {
        case .csv:  return try exportCSV(results)
        case .json: return try exportJSON(results)
        }
    }

    // MARK: - CSV

    private func exportCSV(_ results: [TestResult]) throws -> Data {
        var lines = ["timestamp,ssid,bssid,assoc,v4_addr,v4_gw,v4_net,v4_mtu,v4_dns,v6_addr,v6_gw,v6_net,v6_mtu,v6_dns"]
        let fmt = ISO8601DateFormatter()
        for r in results {
            let ts = r.startedAt.map { fmt.string(from: $0) } ?? ""
            let row = [ts, esc(r.ssid), r.bssid,
                       csv(r.assoc), csv(r.v4Addr), csv(r.v4GW),  csv(r.v4Net),
                       csv(r.v4MTU), csv(r.v4DNS),  csv(r.v6Addr), csv(r.v6GW),
                       csv(r.v6Net), csv(r.v6MTU),  csv(r.v6DNS)].joined(separator: ",")
            lines.append(row)
        }
        return lines.joined(separator: "\n").data(using: .utf8)!
    }

    private func csv(_ s: TestItemStatus) -> String {
        switch s {
        case .pending:          return "pending"
        case .running:          return "running"
        case .pass(let d):      return d ?? "pass"
        case .fail(let d):      return d ?? "fail"
        case .skip:             return "skip"
        case .stopped:          return "stopped"
        }
    }

    private func esc(_ s: String) -> String {
        guard s.contains(",") || s.contains("\"") || s.contains("\n") else { return s }
        return "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    // MARK: - JSON

    private func exportJSON(_ results: [TestResult]) throws -> Data {
        let fmt = ISO8601DateFormatter()
        let rows: [[String: Any]] = results.map { r in
            var d: [String: Any] = [
                "ssid":     r.ssid,
                "bssid":    r.bssid,
                "tested_at": r.startedAt.map { fmt.string(from: $0) } ?? "",
                "assoc":    csv(r.assoc),
                "v4_addr":  csv(r.v4Addr),
                "v4_gw":    csv(r.v4GW),
                "v4_net":   csv(r.v4Net),
                "v4_mtu":   csv(r.v4MTU),
                "v4_dns":   csv(r.v4DNS),
                "v6_addr":  csv(r.v6Addr),
                "v6_gw":    csv(r.v6GW),
                "v6_net":   csv(r.v6Net),
                "v6_mtu":   csv(r.v6MTU),
                "v6_dns":   csv(r.v6DNS),
            ]
            if let a = r.ipv4Address  { d["v4_addr_value"] = a }
            if let g = r.ipv4Gateway  { d["v4_gateway"] = g }
            if !r.ipv4DNSServers.isEmpty { d["v4_dns_servers"] = r.ipv4DNSServers }
            if let a = r.ipv6Address  { d["v6_addr_value"] = a }
            if let g = r.ipv6Gateway  { d["v6_gateway"] = g }
            if !r.ipv6DNSServers.isEmpty { d["v6_dns_servers"] = r.ipv6DNSServers }
            return d
        }
        let envelope: [String: Any] = [
            "exported_at": fmt.string(from: Date()),
            "results": rows
        ]
        return try JSONSerialization.data(withJSONObject: envelope, options: [.prettyPrinted, .sortedKeys])
    }
}
```

- [ ] **Step 4: テストがパスすることを確認**

```bash
xcodebuild test -scheme MacWifiChecker -destination 'platform=macOS' \
  -only-testing:MacWifiCheckerTests/ResultExporterTests 2>&1 | grep -E "PASS|FAIL|Executed"
```

期待: 全テスト PASS。

- [ ] **Step 5: コミット**

```bash
git add MacWifiChecker/Utilities/ResultExporter.swift MacWifiCheckerTests/ResultExporterTests.swift
git commit -m "feat: add ResultExporter (CSV/JSON) with TDD"
```

---

## Task 5: WiFiService（位置情報認証 + CoreWLAN ラッパー）

**Files:**
- Create: `MacWifiChecker/Services/WiFiService.swift`

- [ ] **Step 1: `WiFiService.swift` を作成**

```swift
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
                    try iface.associate(toNetwork: network, password: psk)
                    cont.resume()
                } catch {
                    cont.resume(throwing: WiFiError.associationFailed(underlying: error))
                }
            }
        }
        // 接続後の BSSID を検証
        let actual = iface.bssid?.lowercased()
        guard actual == key else {
            throw WiFiError.bssidMismatch(expected: bssid, actual: actual)
        }
    }

    func disassociate() {
        client.interface()?.disassociate()
    }

    // MARK: - Helpers

    private func makeAPInfo(from net: CWNetwork) -> APInfo {
        let bssid = net.bssid?.lowercased() ?? "unknown"
        let band: String
        switch net.wlanChannel?.channelBand {
        case .band2GHz: band = "2.4GHz"
        case .band5GHz: band = "5GHz"
        default:        band = "6GHz"
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
```

- [ ] **Step 2: ビルド確認**

```bash
xcodebuild build -scheme MacWifiChecker -destination 'platform=macOS' 2>&1 | tail -3
```

期待: `** BUILD SUCCEEDED **`

- [ ] **Step 3: コミット**

```bash
git add MacWifiChecker/Services/WiFiService.swift
git commit -m "feat: add WiFiService (CoreWLAN scan/associate + CLLocation auth)"
```

---

## Task 6: NetworkTestService（ShellRunner + 11テスト + DHCP/RAポーリング）

**Files:**
- Create: `MacWifiChecker/Services/NetworkTestService.swift`

- [ ] **Step 1: `NetworkTestService.swift` を作成（ShellRunner + DHCP/RA ポーリング）**

```swift
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
    func run(_ args: [String]) async throws -> String {
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                proc.arguments = args
                let outPipe = Pipe(), errPipe = Pipe()
                proc.standardOutput = outPipe
                proc.standardError  = errPipe
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
        } onCancel: { }
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
    func waitForIPv4(timeoutSeconds: Double = 15) async throws -> IPv4Info {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            try Task.checkCancellation()
            if let info = try? await fetchIPv4Info() { return info }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        throw ShellError.failed(exitCode: 1, output: "DHCPタイムアウト: \(timeoutSeconds)秒以内にIPv4アドレスが取得できませんでした")
    }

    /// RA/SLAAC で IPv6 グローバルアドレスが取得されるまでポーリングする（最大 timeoutSeconds 秒）
    func waitForIPv6(timeoutSeconds: Double = 20) async throws -> IPv6Info {
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
            .flatMap { $0.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) }
            ?? ""

        // DNS（scutil --dns からインターフェース固有のサーバーを取得）
        let scutilOut = (try? await run(["scutil", "--dns"])) ?? ""
        let dnsServers = parseScutilIPv6DNS(scutilOut)

        return IPv6Info(address: addr, gateway: gw, dnsServers: dnsServers)
    }

    // MARK: - 11 テスト項目

    /// テスト 1: Association（WiFiService.associate で完了済み）→ TestResult に記録するだけ
    /// このメソッドは association 後の BSSID 検証に使う
    func testAssoc(result: inout TestResult, expectedBSSID: String) {
        // association 成功は呼び出し側（AppViewModel）が保証済み
        result.assoc = .pass()
    }

    /// テスト 2: IPv4 DHCP アドレス取得
    func testV4Addr(result: inout TestResult) async throws -> IPv4Info {
        let info = try await waitForIPv4()
        result.v4Addr = .pass(detail: info.address)
        result.ipv4Address   = info.address
        result.ipv4Gateway   = info.gateway
        result.ipv4DNSServers = info.dnsServers
        return info
    }

    /// テスト 3: IPv4 デフォルトゲートウェイへの ping
    func testV4GW(result: inout TestResult, gateway: String) async {
        do {
            _ = try await run(["ping", "-c1", "-W3000", gateway])
            result.v4GW = .pass()
        } catch {
            result.v4GW = .fail(detail: "ping失敗: \(gateway)")
        }
    }

    /// テスト 4: IPv4 インターネット疎通
    func testV4Net(result: inout TestResult, target: String) async {
        do {
            _ = try await run(["ping", "-c1", "-W5000", target])
            result.v4Net = .pass()
        } catch {
            result.v4Net = .fail(detail: "ping失敗: \(target)")
        }
    }

    /// テスト 5: IPv4 MTU（DF ビットを立てて二分探索）
    func testV4MTU(result: inout TestResult, gateway: String) async {
        let mtu = await binarySearchMTU(target: gateway, lo: 100, hi: 1472, family: .v4)
        if mtu > 0 {
            result.v4MTU = .pass(detail: "\(mtu + 28)")  // IP(20) + ICMP(8) + payload = MTU
        } else {
            result.v4MTU = .fail(detail: "MTU検出失敗")
        }
    }

    /// テスト 6: IPv4 DNS 解決
    func testV4DNS(result: inout TestResult, server: String, target: String) async {
        do {
            _ = try await run(["dig", "@\(server)", target, "A", "+time=5", "+tries=1"])
            result.v4DNS = .pass()
        } catch {
            result.v4DNS = .fail(detail: "dig失敗: @\(server) \(target)")
        }
    }

    /// テスト 7-11: IPv6 系
    func testV6Addr(result: inout TestResult) async throws -> IPv6Info {
        let info = try await waitForIPv6()
        result.v6Addr = .pass(detail: info.address)
        result.ipv6Address    = info.address
        result.ipv6Gateway    = info.gateway
        result.ipv6DNSServers = info.dnsServers
        return info
    }

    func testV6GW(result: inout TestResult, gateway: String) async {
        do {
            _ = try await run(["ping6", "-c1", gateway])
            result.v6GW = .pass()
        } catch {
            result.v6GW = .fail(detail: "ping6失敗: \(gateway)")
        }
    }

    func testV6Net(result: inout TestResult, target: String) async {
        do {
            _ = try await run(["ping6", "-c1", target])
            result.v6Net = .pass()
        } catch {
            result.v6Net = .fail(detail: "ping6失敗: \(target)")
        }
    }

    func testV6MTU(result: inout TestResult, gateway: String) async {
        let payload = await binarySearchMTU(target: gateway, lo: 1232, hi: 1452, family: .v6)
        if payload > 0 {
            result.v6MTU = .pass(detail: "\(payload + 48)")  // IPv6(40) + ICMPv6(8) + payload
        } else {
            result.v6MTU = .fail(detail: "MTU検出失敗")
        }
    }

    func testV6DNS(result: inout TestResult, server: String, target: String) async {
        do {
            _ = try await run(["dig", "@\(server)", target, "AAAA", "+time=5", "+tries=1"])
            result.v6DNS = .pass()
        } catch {
            result.v6DNS = .fail(detail: "dig失敗: @\(server) \(target)")
        }
    }

    // MARK: - MTU 二分探索

    private enum IPFamily { case v4, v6 }

    /// 指定範囲でペイロードサイズを二分探索して、通る最大ペイロードバイト数を返す。
    private func binarySearchMTU(target: String, lo: Int, hi: Int, family: IPFamily) async -> Int {
        var lo = lo, hi = hi, best = 0
        while lo <= hi {
            let mid = (lo + hi) / 2
            let ok = await pingOnce(target: target, payloadSize: mid, family: family)
            if ok { best = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return best
    }

    private func pingOnce(target: String, payloadSize: Int, family: IPFamily) async -> Bool {
        do {
            switch family {
            case .v4:
                _ = try await run(["ping", "-c1", "-W2000", "-D", "-s\(payloadSize)", target])
            case .v6:
                _ = try await run(["ping6", "-c1", "-s\(payloadSize)", target])
            }
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
```

- [ ] **Step 2: ビルド確認**

```bash
xcodebuild build -scheme MacWifiChecker -destination 'platform=macOS' 2>&1 | tail -3
```

期待: `** BUILD SUCCEEDED **`

- [ ] **Step 3: コミット**

```bash
git add MacWifiChecker/Services/NetworkTestService.swift
git commit -m "feat: add NetworkTestService (ShellRunner, 11 tests, DHCP/RA polling, MTU binary search)"
```

---

## Task 7: AppViewModel（@Observable 状態管理・テスト制御）

**Files:**
- Create: `MacWifiChecker/ViewModels/AppViewModel.swift`

- [ ] **Step 1: `AppViewModel.swift` を作成**

```swift
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

    init(wifiService: WiFiService = WiFiService(), networkTester: NetworkTestService = NetworkTestService()) {
        self.wifiService = wifiService
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

        defer {
            results[ap.bssid]?.finishedAt = Date()
            wifiService.disassociate()
        }

        // --- Association ---
        testStatus = .running(bssid: ap.bssid, step: "Association")
        result.assoc = .running
        results[ap.bssid] = result
        do {
            try await wifiService.associate(bssid: ap.bssid, psk: psk)
            result.assoc = .pass()
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
```

- [ ] **Step 2: AppViewModel を App から注入するよう `MacWifiCheckerApp.swift` を更新**

```swift
import SwiftUI

@main
struct MacWifiCheckerApp: App {
    @State private var appVM = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appVM)
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            // ⌘W でウィンドウ閉じを無効化（ターミナル的使い方を想定）
        }
    }
}
```

- [ ] **Step 3: ビルド確認**

```bash
xcodebuild build -scheme MacWifiChecker -destination 'platform=macOS' 2>&1 | tail -3
```

期待: `** BUILD SUCCEEDED **`

- [ ] **Step 4: コミット**

```bash
git add MacWifiChecker/ViewModels/AppViewModel.swift MacWifiChecker/App/MacWifiCheckerApp.swift
git commit -m "feat: add AppViewModel (@Observable, test orchestration, scan/stop/export)"
```

---

## Task 8: ResultMatrixView（スクロール可能な結果マトリックス）

**Files:**
- Create: `MacWifiChecker/Views/ResultMatrixView.swift`

- [ ] **Step 1: `ResultMatrixView.swift` を作成**

```swift
import SwiftUI

struct ResultMatrixView: View {
    @Environment(AppViewModel.self) private var vm

    private let columns = ["Assoc","v4 Addr","v4 GW","v4 Net","v4 MTU","v4 DNS",
                           "v6 Addr","v6 GW","v6 Net","v6 MTU","v6 DNS"]
    private let colWidth: CGFloat = 60
    private let bssidWidth: CGFloat = 155

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダーバー（Stop/Restart + ステータス）
            HStack(spacing: 10) {
                Text("TEST RESULTS")
                    .font(.caption).bold().foregroundStyle(.secondary)

                if case .running(_, let step) = vm.testStatus {
                    Text("⏳ \(step)")
                        .font(.caption).foregroundStyle(.yellow)
                }
                if vm.testStatus == .complete {
                    Text("✓ 完了").font(.caption).foregroundStyle(.green)
                }
                Spacer()
                stopRestartButton
                exportButton
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)

            Divider()

            // マトリックス本体（縦+横スクロール）
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    // ヘッダー行
                    HStack(spacing: 0) {
                        Text("BSSID").frame(width: bssidWidth, alignment: .leading)
                            .font(.caption).bold().foregroundStyle(.secondary)
                        ForEach(columns, id: \.self) { col in
                            Text(col).frame(width: colWidth)
                                .font(.caption).bold().foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .windowBackgroundColor))

                    Divider()

                    // 結果行
                    ForEach(sortedResults) { result in
                        ResultRowView(result: result, colWidth: colWidth, bssidWidth: bssidWidth)
                            .background(isRunning(result.bssid) ? Color.yellow.opacity(0.07) : Color.clear)
                        Divider()
                    }
                }
            }
        }
    }

    private var sortedResults: [TestResult] {
        vm.results.values.sorted { $0.ssid == $1.ssid ? $0.bssid < $1.bssid : $0.ssid < $1.ssid }
    }

    private func isRunning(_ bssid: String) -> Bool {
        if case .running(let b, _) = vm.testStatus { return b == bssid }
        return false
    }

    @ViewBuilder
    private var stopRestartButton: some View {
        switch vm.testStatus {
        case .running:
            Button("■ Stop") { vm.stopTest() }
                .buttonStyle(.borderedProminent)
                .tint(.red)
        case .stopped, .complete:
            Button("▶ Restart") { vm.startTest() }
                .buttonStyle(.borderedProminent)
                .tint(.green)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var exportButton: some View {
        Menu("⬇ Export") {
            Button("CSV でエクスポート…") { showExportPanel(format: .csv) }
            Button("JSON でエクスポート…") { showExportPanel(format: .json) }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(vm.results.isEmpty)
    }

    private func showExportPanel(format: ExportFormat) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = format == .csv ? "wifi-test-results.csv" : "wifi-test-results.json"
        panel.allowedContentTypes = [format == .csv ? .commaSeparatedText : .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        vm.exportResults(format: format, to: url)
    }
}

// MARK: - ResultRowView

private struct ResultRowView: View {
    let result: TestResult
    let colWidth: CGFloat
    let bssidWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text(result.bssid).font(.system(.caption, design: .monospaced))
                Text(result.ssid).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: bssidWidth, alignment: .leading)

            let items: [TestItemStatus] = [
                result.assoc, result.v4Addr, result.v4GW, result.v4Net,
                result.v4MTU, result.v4DNS,
                result.v6Addr, result.v6GW, result.v6Net,
                result.v6MTU, result.v6DNS
            ]
            ForEach(Array(items.enumerated()), id: \.offset) { _, status in
                StatusCell(status: status, width: colWidth)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }
}

private struct StatusCell: View {
    let status: TestItemStatus
    let width: CGFloat

    var body: some View {
        Text(status.displayText)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(color)
            .frame(width: width)
            .multilineTextAlignment(.center)
    }

    private var color: Color {
        switch status {
        case .pass:    return .green
        case .fail:    return .red
        case .running: return .yellow
        case .skip, .pending: return .secondary
        case .stopped: return .orange
        }
    }
}

```

- [ ] **Step 2: ビルド確認**

```bash
xcodebuild build -scheme MacWifiChecker -destination 'platform=macOS' 2>&1 | tail -3
```

- [ ] **Step 3: コミット**

```bash
git add MacWifiChecker/Views/ResultMatrixView.swift
git commit -m "feat: add ResultMatrixView (scrollable 11-column test matrix)"
```

---

## Task 9: APListView（AP 一覧・フィルタ・チェック・cfg バッジ）

**Files:**
- Create: `MacWifiChecker/Views/APListView.swift`

- [ ] **Step 1: `APListView.swift` を作成**

```swift
import SwiftUI

struct APListView: View {
    @Environment(AppViewModel.self) private var vm

    var body: some View {
        @Bindable var bvm = vm
        VStack(spacing: 0) {
            // フィルタバー
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("SSID / BSSID でフィルタ…", text: $bvm.filterText)
                    .textFieldStyle(.plain)
                Spacer()
                Button("全選択") { vm.selectAll() }.controlSize(.small)
                Button("全クリア") { vm.clearAll() }.controlSize(.small)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)

            Divider()

            // AP テーブルヘッダー
            HStack(spacing: 0) {
                Text("").frame(width: 24)
                Text("SSID").frame(width: 140, alignment: .leading).font(.caption).bold().foregroundStyle(.secondary)
                Text("BSSID").frame(width: 155, alignment: .leading).font(.caption).bold().foregroundStyle(.secondary)
                Text("Band").frame(width: 55, alignment: .leading).font(.caption).bold().foregroundStyle(.secondary)
                Text("RSSI").frame(width: 65, alignment: .trailing).font(.caption).bold().foregroundStyle(.secondary)
                Text("PSK Override").frame(minWidth: 80, alignment: .leading).font(.caption).bold().foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // AP リスト（縦スクロール）
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(vm.filteredAPs) { ap in
                        APRowView(ap: ap)
                        Divider()
                    }
                }
            }

            Divider()

            // フッター: AP数サマリー
            HStack {
                Text("\(vm.aps.count) APs found · \(vm.selectedAPs.count) selected")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - APRowView

private struct APRowView: View {
    @Environment(AppViewModel.self) private var vm
    let ap: APInfo
    @State private var pskInput: String = ""

    var body: some View {
        @Bindable var bvm = vm
        HStack(spacing: 0) {
            // チェックボックス
            Toggle("", isOn: Binding(
                get: { ap.isSelected },
                set: { _ in vm.toggleSelection(bssid: ap.bssid) }
            ))
            .toggleStyle(.checkbox)
            .frame(width: 24)

            // SSID + cfg バッジ
            HStack(spacing: 4) {
                Text(ap.ssid)
                    .font(.system(size: 12))
                    .lineLimit(1)
                if ap.fromConfig {
                    Text("cfg")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }
            }
            .frame(width: 140, alignment: .leading)

            // BSSID
            Text(ap.bssid)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.green)
                .frame(width: 155, alignment: .leading)

            // Band
            Text(ap.band)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 55, alignment: .leading)

            // RSSI
            Text("\(ap.rssi) dBm")
                .font(.caption)
                .foregroundStyle(rssiColor(ap.rssi))
                .frame(width: 65, alignment: .trailing)

            // PSK Override
            TextField("global を使用", text: Binding(
                get: { ap.pskOverride ?? "" },
                set: { newVal in
                    guard let i = vm.aps.firstIndex(where: { $0.bssid == ap.bssid }) else { return }
                    vm.aps[i].pskOverride = newVal.isEmpty ? nil : newVal
                }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11))
            .frame(minWidth: 100)
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(ap.fromConfig ? Color.blue.opacity(0.06) : Color.clear)
        .overlay(alignment: .leading) {
            if ap.fromConfig {
                Rectangle().frame(width: 3).foregroundStyle(Color.blue)
            }
        }
    }

    private func rssiColor(_ rssi: Int) -> Color {
        switch rssi {
        case ..<(-80): return .red
        case ..<(-70): return .orange
        default:       return .green
        }
    }
}
```

- [ ] **Step 2: ビルド確認**

```bash
xcodebuild build -scheme MacWifiChecker -destination 'platform=macOS' 2>&1 | tail -3
```

- [ ] **Step 3: コミット**

```bash
git add MacWifiChecker/Views/APListView.swift
git commit -m "feat: add APListView (table, filter, checkbox, cfg badge, PSK override)"
```

---

## Task 10: SettingsView + ContentView（最終アセンブリ）

**Files:**
- Create: `MacWifiChecker/Views/SettingsView.swift`
- Create: `MacWifiChecker/Views/ContentView.swift`

- [ ] **Step 1: `SettingsView.swift` を作成**

```swift
import SwiftUI

struct SettingsView: View {
    @Environment(AppViewModel.self) private var vm

    var body: some View {
        @Bindable var bvm = vm
        VStack(alignment: .leading, spacing: 12) {
            Text("⚙ SETTINGS")
                .font(.caption).bold().foregroundStyle(.secondary)

            // 設定ファイル状態
            if let url = vm.configFileURL {
                HStack(spacing: 6) {
                    Image(systemName: "doc.fill").foregroundStyle(.green)
                    Text(url.lastPathComponent)
                        .font(.caption).foregroundStyle(.green)
                        .lineLimit(1).truncationMode(.middle)
                }
                .padding(6)
                .background(Color.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Group {
                LabeledField("Global PSK") {
                    SecureField("パスフレーズ", text: $bvm.config.passphrase)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledField("IPv4 Ping Target") {
                    TextField("1.1.1.1", text: $bvm.config.ipv4PingTarget)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledField("IPv6 Ping Target") {
                    TextField("2606:4700:4700::1111", text: $bvm.config.ipv6PingTarget)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledField("DNS Lookup Target") {
                    TextField("www.google.com", text: $bvm.config.dnsLookupTarget)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Spacer()

            // エラー表示
            if let err = vm.errorMessage {
                Text(err).font(.caption).foregroundStyle(.red).lineLimit(3)
            }

            // Start ボタン
            Button(action: { vm.startTest() }) {
                Label("Start (\(vm.selectedAPs.count))", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.large)
            .disabled(vm.selectedAPs.isEmpty || vm.isRunning)
        }
        .padding(12)
        .frame(width: 220)
    }
}

private struct LabeledField<Content: View>: View {
    let label: String
    let content: Content
    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content
        }
    }
}
```

- [ ] **Step 2: `ContentView.swift` を作成**

```swift
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppViewModel.self) private var vm

    var body: some View {
        VStack(spacing: 0) {
            // ツールバー
            toolbar

            Divider()

            // 上段: AP一覧 + 設定（横分割）
            HSplitView {
                APListView()
                    .frame(minWidth: 400)
                SettingsView()
            }
            .frame(minHeight: 220, idealHeight: 280)

            Divider()

            // 下段: 結果マトリックス
            ResultMatrixView()
                .frame(minHeight: 200)
        }
        .task {
            vm.requestLocationPermission()    // ← 位置情報ダイアログ
        }
        .alert("エラー", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.blue)
            Text("Mac Wi-Fi Checker")
                .font(.headline)

            Spacer()

            // 設定ファイル UI
            configFileUI

            Button("🔄 Scan") {
                Task { await vm.scan() }
            }
            .buttonStyle(.bordered)
            .disabled(vm.isRunning)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var configFileUI: some View {
        HStack(spacing: 4) {
            Image(systemName: "doc").foregroundStyle(.secondary)
            Text(vm.configFileURL?.lastPathComponent ?? "設定ファイル未読み込み")
                .font(.caption)
                .foregroundStyle(vm.configFileURL != nil ? .primary : .secondary)
                .frame(maxWidth: 160)
                .lineLimit(1)
                .truncationMode(.middle)

            Button("Load…") { showLoadPanel() }
                .controlSize(.small)

            Button("Save") {
                if let url = vm.configFileURL {
                    vm.saveConfig(to: url)
                } else {
                    showSavePanel()
                }
            }
            .controlSize(.small)
            .disabled(vm.configFileURL == nil)

            Button("Save As…") { showSavePanel() }
                .controlSize(.small)
        }
        .padding(5)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func showLoadPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = "Wi-Fi Checker 設定ファイルを選択してください"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        vm.loadConfig(from: url)
        Task { await vm.scan() }   // 設定読み込み後に自動スキャン
    }

    private func showSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "wifi-checker-config.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        vm.saveConfig(to: url)
    }
}
```

- [ ] **Step 3: ビルド確認**

```bash
xcodebuild build -scheme MacWifiChecker -destination 'platform=macOS' 2>&1 | tail -3
```

期待: `** BUILD SUCCEEDED **`

- [ ] **Step 4: 全テストを通す**

```bash
xcodebuild test -scheme MacWifiChecker -destination 'platform=macOS' 2>&1 | grep -E "PASS|FAIL|Executed"
```

期待: 全テスト PASS。

- [ ] **Step 5: コミット**

```bash
git add MacWifiChecker/Views/SettingsView.swift MacWifiChecker/Views/ContentView.swift
git commit -m "feat: add SettingsView + ContentView (final assembly, toolbar with config file UI)"
```

---

## Task 11: 手動統合テストチェックリスト

- [ ] **Xcode でアプリを起動**

  Xcode で `MacWifiChecker` スキームを選択して Run（⌘R）。

- [ ] **位置情報ダイアログを確認**

  初回起動時に「位置情報へのアクセスを許可しますか？」ダイアログが表示されること。  
  「許可」を選択する。

- [ ] **スキャン動作を確認**

  「🔄 Scan」をクリックすると AP 一覧が表示されること。  
  SSID / BSSID / Band / RSSI が正しく表示されること。

- [ ] **フィルタを確認**

  フィルタボックスに SSID の一部を入力するとリストが絞り込まれること。  
  フィルタをクリアするとリストが元に戻ること。

- [ ] **Config ファイルの読み込みを確認**

  以下の内容で `test-config.json` を作成してツールバーの Load… から読み込む:
  ```json
  {
    "passphrase": "yourpassphrase",
    "ipv4_ping_target": "1.1.1.1",
    "ipv6_ping_target": "2606:4700:4700::1111",
    "dns_lookup_target": "www.google.com",
    "auto_select": {
      "ssids": [],
      "bssids": ["スキャンで見つかった BSSID を1つ記入"]
    },
    "ssid_psk_overrides": {}
  }
  ```
  → 指定した BSSID が自動チェックされ `cfg` バッジが表示されること。

- [ ] **1つの AP でテストを実行**

  AP を1つ選択して「Start (1)」をクリック。  
  下段マトリックスに各テストが順次更新されること（`…` → `✓` or `✗`）。  
  ステータスバーに現在のステップが表示されること。

- [ ] **Stop ボタンを確認**

  テスト実行中に「■ Stop」をクリック。  
  未実行の項目が `■`（stopped）になること。  
  Restart ボタンが表示されること。

- [ ] **CSV エクスポートを確認**

  テスト完了後、「⬇ Export」→「CSV でエクスポート…」で保存。  
  ファイルをテキストエディタで開き、ヘッダーと結果行が正しく記録されていること。

- [ ] **JSON エクスポートを確認**

  「⬇ Export」→「JSON でエクスポート…」で保存。  
  `exported_at` / `results` / IP アドレス詳細が含まれていること。

- [ ] **コミット**

```bash
git add .
git commit -m "docs: add manual integration test notes"
```

---

## 補足: 既知の注意点

| 項目 | 内容 |
|------|------|
| CoreWLAN Sendable | `CWNetwork` は `Sendable` 非準拠。Xcode の警告が出るが機能には影響しない |
| associate スレッド | `CWInterface.associate` は内部でメインスレッドチェックをする場合がある。失敗時は `DispatchQueue.main.async` でラップする |
| IPv6 DNS 取得 | `scutil --dns` の出力フォーマットは macOS バージョンで変わる場合がある。失敗時は v6 DNS テストを skip にする |
| ping -D フラグ | macOS の `ping -D` は DF bit セットを意味する（Linux の `-D` はタイムスタンプ表示とは異なる） |
| BSSID 大文字小文字 | CoreWLAN は小文字で返す場合が多いが正規化して比較すること |
