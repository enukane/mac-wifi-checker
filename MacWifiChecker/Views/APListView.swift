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
            // maxWidth: .infinity で行の TextField と同じ幅になるようにする
            HStack(spacing: 0) {
                Text("").frame(width: 24)
                Text("SSID").frame(width: 140, alignment: .leading).font(.caption).bold().foregroundStyle(.secondary)
                Text("BSSID").frame(width: 155, alignment: .leading).font(.caption).bold().foregroundStyle(.secondary)
                Text("Band").frame(width: 55, alignment: .leading).font(.caption).bold().foregroundStyle(.secondary)
                Text("RSSI").frame(width: 65, alignment: .trailing).font(.caption).bold().foregroundStyle(.secondary)
                Text("PSK Override")
                    .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                    .font(.caption).bold().foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // AP リスト（縦スクロール）
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(vm.filteredAPs) { ap in
                        APRowView(bssid: ap.bssid)
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
    let bssid: String

    var body: some View {
        // vm.aps を直接読むことで @Observable のトラッキングを確立し、
        // isSelected の変化で確実に再レンダリングされるようにする
        guard let ap = vm.aps.first(where: { $0.bssid == bssid }) else {
            return AnyView(EmptyView())
        }
        return AnyView(rowContent(ap: ap))
    }

    @ViewBuilder
    private func rowContent(ap: APInfo) -> some View {
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

            // PSK Override（padding(.horizontal, 4) を除去してヘッダーと列位置を一致させる）
            TextField("global を使用", text: Binding(
                get: { ap.pskOverride ?? "" },
                set: { newVal in
                    vm.setPSKOverride(for: ap.bssid, psk: newVal.isEmpty ? nil : newVal)
                }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11))
            .frame(minWidth: 100)
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
