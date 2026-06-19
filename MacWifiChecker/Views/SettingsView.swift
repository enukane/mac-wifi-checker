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
