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
        case .fail:             return "fail"
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
