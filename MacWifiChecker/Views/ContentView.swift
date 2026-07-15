import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppViewModel.self) private var vm

    var body: some View {
        VStack(spacing: 0) {
            // ツールバー
            toolbar

            Divider()

            // 上段/下段を VSplitView で分割 → ウィンドウサイズに追従
            VSplitView {
                // 上段: AP一覧 + 設定（横分割）
                HSplitView {
                    APListView()
                        .frame(minWidth: 400)
                    SettingsView()
                }
                .frame(minHeight: 180, idealHeight: 280)

                // 下段: 結果マトリックス
                ResultMatrixView()
                    .frame(minHeight: 150)
            }
            .frame(maxHeight: .infinity)  // VStack 内で VSplitView が縦に伸びるよう指示
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
