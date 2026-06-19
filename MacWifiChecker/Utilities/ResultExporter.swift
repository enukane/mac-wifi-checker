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
                       statusString(r.assoc), statusString(r.v4Addr), statusString(r.v4GW),  statusString(r.v4Net),
                       statusString(r.v4MTU), statusString(r.v4DNS),  statusString(r.v6Addr), statusString(r.v6GW),
                       statusString(r.v6Net), statusString(r.v6MTU),  statusString(r.v6DNS)].joined(separator: ",")
            lines.append(row)
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    private func statusString(_ s: TestItemStatus) -> String {
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
        guard s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r") else { return s }
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
                "assoc":    statusString(r.assoc),
                "v4_addr":  statusString(r.v4Addr),
                "v4_gw":    statusString(r.v4GW),
                "v4_net":   statusString(r.v4Net),
                "v4_mtu":   statusString(r.v4MTU),
                "v4_dns":   statusString(r.v4DNS),
                "v6_addr":  statusString(r.v6Addr),
                "v6_gw":    statusString(r.v6GW),
                "v6_net":   statusString(r.v6Net),
                "v6_mtu":   statusString(r.v6MTU),
                "v6_dns":   statusString(r.v6DNS),
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
