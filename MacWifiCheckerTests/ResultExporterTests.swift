import XCTest
@testable import MacWifiChecker

final class ResultExporterTests: XCTestCase {
    var sut: ResultExporter!

    override func setUpWithError() throws {
        try super.setUpWithError()
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
        var result = TestResult(bssid: "aa:bb:cc:dd:ee:03", ssid: "net,work")
        result.assoc = .pass()

        let data = try sut.export([result], format: .csv)
        let text = String(data: data, encoding: .utf8)!
        XCTAssertTrue(text.contains("\"net,work\""))
    }

    func test_exportCSV_ssidWithQuote_escapedCorrectly() throws {
        let result = TestResult(bssid: "aa:bb:cc:dd:ee:04", ssid: "net\"work")
        let data = try sut.export([result], format: .csv)
        let text = String(data: data, encoding: .utf8)!
        XCTAssertTrue(text.contains("\"net\"\"work\""))
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
