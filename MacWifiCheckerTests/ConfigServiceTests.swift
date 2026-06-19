import XCTest
@testable import MacWifiChecker

final class ConfigServiceTests: XCTestCase {
    var sut: ConfigService!
    var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        sut = ConfigService()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
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

    func test_load_invalidJSON_throws() throws {
        let url = tempDir.appendingPathComponent("bad.json")
        try "not json".data(using: .utf8)!.write(to: url)
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
