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
