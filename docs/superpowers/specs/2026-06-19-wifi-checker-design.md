# Mac Wi-Fi Checker — 設計ドキュメント

**作成日**: 2026-06-19  
**対象**: macOS 14 Sonoma 以降  
**配布**: チーム内 Ad Hoc + GitHub Releases（ノータリゼーション対応、非サンドボックス）

---

## 1. 概要

展示会・イベント会場において、複数のWi-Fi AP（アクセスポイント）を **BSSID指定** で順番に接続し、IPv4/IPv6の疎通・DHCP/RA・MTU・DNSを一括検証するmacOS GUIアプリ。

テスト中はMacのWi-Fi接続が切り替わることを許容する（検証専用Mac、または現地作業での利用を想定）。

---

## 2. 使用シナリオ

- 展示会インフラ担当者が現地でAPごとの動作を素早く確認する
- 1台のMacBookで複数APを順番にテストし、結果をマトリックス形式で一覧表示
- 結果はCSV/JSONでエクスポートして報告書・記録に利用

---

## 3. 技術スタック

| 要素 | 採用技術 |
|------|----------|
| UI | SwiftUI（macOS 14+）|
| Wi-Fi管理 | CoreWLAN（`CWWiFiClient`, `CWInterface`, `CWNetwork`）|
| DHCP/RA情報取得 | SystemConfiguration framework（`SCDynamicStore`）|
| ping / MTU | サブプロセス（`ping -D -s`, `ping6`）|
| DNS テスト | サブプロセス（`dig @<server> <target> A/AAAA`）|
| 設定ファイル | JSON（`Codable`）|
| 並行処理 | Swift Concurrency（`async/await`, `Task`）|
| エクスポート | CSV / JSON、`NSSavePanel` でファイル保存先選択 |

---

## 4. アーキテクチャ

### 4.1 ファイル構成

```
MacWifiChecker/
├── App/
│   └── MacWifiCheckerApp.swift         # エントリポイント、AppViewModel注入
├── Models/
│   ├── APInfo.swift                    # SSID, BSSID, band, RSSI, isSelected, pskOverride
│   ├── TestResult.swift                # AP1つ分の11項目テスト結果 + メタ情報
│   ├── AppConfig.swift                 # Codable: PSK / ping先 / auto_select / psk_overrides
│   └── TestStatus.swift                # enum: .idle / .running(ap:step:) / .stopped / .complete
├── Services/
│   ├── WiFiService.swift               # CoreWLAN wrapper: scan / associate / disassociate
│   ├── NetworkTestService.swift        # 11テストを順番に実行（async throws）
│   └── ConfigService.swift             # JSON load/save, auto-selectルール適用
├── ViewModels/
│   └── AppViewModel.swift              # @Observable: 全状態管理、テスト制御タスク管理
├── Views/
│   ├── ContentView.swift               # VSplitView: 上段（APリスト+設定）/ 下段（結果）
│   ├── APListView.swift                # ScrollView + Table: AP一覧・フィルタ・チェック
│   ├── SettingsView.swift              # 設定パネル: PSK・ping先・Start/Export
│   └── ResultMatrixView.swift          # ScrollView（縦+横）+ テスト結果テーブル
└── Utilities/
    └── ResultExporter.swift            # CSV / JSON エクスポート実装
```

### 4.2 データフロー

```
起動
  └─ ConfigService.loadLast() → AppViewModel.config に適用（UserDefaults でパス記憶）

[Scan ボタン]
  └─ WiFiService.scan() → [APInfo]（同一SSIDの複数BSSIDは別エントリ）
       └─ ConfigService.applyAutoSelect([APInfo]) → isSelected フラグを更新

[Load Config ボタン]
  └─ NSOpenPanel → ConfigService.load(url:) → config 更新 + applyAutoSelect 再実行

[Save Config ボタン]
  └─ NSSavePanel → ConfigService.save(config, url:)

[Start ボタン]
  └─ AppViewModel.startTest()
       └─ Task { for ap in selectedAPs (順次):
            1. WiFiService.associate(ap, psk)         ← CWNetwork BSSID指定
            2. wait for DHCP（SCDynamicStore poll, timeout 15s）
            3. IPv4 テスト ×5（各ステップ完了ごとに AppViewModel.results を更新 → UI即時反映）
            4. wait for RA/SLAAC（ifconfig poll, timeout 20s）
            5. IPv6 テスト ×5（各ステップ完了ごとに AppViewModel.results を更新 → UI即時反映）
            6. WiFiService.disassociate()
         }
         ※ results は [BSSID: TestResult] の辞書で、TestResult は各テスト項目を
           .pending / .running / .pass / .fail / .skip で個別管理する

[Stop ボタン]
  └─ currentTask.cancel() → 現在APのテストを中断、結果に .stopped を記録

[Restart ボタン]（全AP完了後 or Stop後に表示）
  └─ results をクリアして startTest() を再実行

[Export ボタン]
  └─ ResultExporter.export(results, format: .csv / .json)
       └─ NSSavePanel でファイル保存
```

---

## 5. UI レイアウト

**縦2分割レイアウト**（`VSplitView`、分割比率はドラッグ調整可）

### 上段: AP一覧 + 設定パネル（`HSplitView`）

**左: AP List**（`ScrollView` 縦スクロール）
- ツールバー: SSID/BSSIDフィルタ入力、全選択ボタン、全クリアボタン
- テーブル列: チェック / SSID / BSSID / Band / RSSI / PSK Override（個別入力）
- Configから自動チェックされた行は `cfg` バッジ＋青い左ボーダーで視覚的に区別
- auto-select状態の解除ボタン（全体）
- AP数・選択数のサマリー表示

**右: Settings パネル**
- 現在読み込み中の設定ファイル表示（パス省略表示）
- Global PSK（パスワードフィールド）
- IPv4 Ping Target（デフォルト: `1.1.1.1`）
- IPv6 Ping Target（デフォルト: `2606:4700:4700::1111`）
- DNS Lookup Target（デフォルト: `www.google.com`）
- `▶ Start (N)` ボタン / `⬇ Export` ボタン

**ツールバー（ウィンドウ上部）**
- アプリ名
- 設定ファイルUI: ファイル名表示 / `Load…` / `Save` ボタン
- `🔄 Scan` ボタン

### 下段: Test Results（`ScrollView` 縦+横スクロール）

- ヘッダー行: `BSSID | Assoc | v4 Addr | v4 GW | v4 Net | v4 MTU | v4 DNS | v6 Addr | v6 GW | v6 Net | v6 MTU | v6 DNS`
- セル凡例: `✓`=成功 / `✗`=失敗 / `—`=スキップ / `…`=実行中 / 数値=MTUバイト数
- テスト中のAP行をハイライト
- `■ Stop` ボタン（テスト中のみ表示）、完了後は `▶ Restart` に切り替え
- ステータスバー: 現在のAP・実行中ステップをリアルタイム表示

---

## 6. テスト項目詳細

| # | 表示名 | 実装 | スキップ条件 |
|---|--------|------|-------------|
| 1 | Assoc | CoreWLAN associate 成功 + 接続後BSSIDが指定BSSIDと一致 | なし |
| 2 | v4 Addr | SCDynamicStore で IPv4アドレス取得（DHCP, timeout 15s）| Assoc 失敗 |
| 3 | v4 GW | `ping -c1 -W3000 <dhcp_gateway>` | v4 Addr 失敗 |
| 4 | v4 Net | `ping -c1 -W5000 <ipv4_ping_target>` | v4 GW 失敗 |
| 5 | v4 MTU | `ping -c1 -D -s1472 <dhcp_gateway>` → 失敗時は二分探索で最大MTUを算出 | v4 GW 失敗 |
| 6 | v4 DNS | `dig @<dhcp_dns> <dns_target> A +time=5 +tries=1` | v4 Addr 失敗 |
| 7 | v6 Addr | `ifconfig en0` でグローバルスコープIPv6アドレス確認（RA/SLAAC, timeout 20s）| Assoc 失敗 |
| 8 | v6 GW | `ping6 -c1 <ra_gateway>` | v6 Addr 失敗 |
| 9 | v6 Net | `ping6 -c1 <ipv6_ping_target>` | v6 GW 失敗 |
| 10 | v6 MTU | `ping6 -c1 -s1452 <ra_gateway>` → 二分探索 | v6 GW 失敗 |
| 11 | v6 DNS | `dig @<ra_dns> <dns_target> AAAA +time=5 +tries=1` | v6 Addr 失敗 |

**MTU二分探索**: IPv4は1472→100バイトの範囲、IPv6は1452→1232バイト（IPv6最小MTU 1280）の範囲で探索。結果としてパスした最大バイト数を表示（ペイロードサイズ、ヘッダー含まず）。

---

## 7. 設定ファイルフォーマット（JSON）

```json
{
  "passphrase": "shownet2026",
  "ipv4_ping_target": "1.1.1.1",
  "ipv6_ping_target": "2606:4700:4700::1111",
  "dns_lookup_target": "www.google.com",
  "auto_select": {
    "ssids": ["shownet-5g", "shownet-2g"],
    "bssids": [
      "11:22:33:44:55:01",
      "11:22:33:44:55:02"
    ]
  },
  "ssid_psk_overrides": {
    "shownet-staff": "staffpass2026"
  }
}
```

**auto_select ルール**:
- `ssids` にマッチ → そのSSIDの全BSSIDを自動チェック
- `bssids` にマッチ → そのBSSIDのみを自動チェック
- 両方指定した場合はORで適用
- 手動チェック/アンチェックは常に優先

---

## 8. エクスポートフォーマット

### CSV
```
timestamp,ssid,bssid,assoc,v4_addr,v4_gw,v4_net,v4_mtu,v4_dns,v6_addr,v6_gw,v6_net,v6_mtu,v6_dns
2026-06-19T10:30:00Z,shownet-5g,11:22:33:44:55:01,pass,pass,pass,pass,1500,pass,pass,pass,pass,1500,pass
2026-06-19T10:31:45Z,shownet-5g,11:22:33:44:55:02,pass,fail,skip,skip,skip,skip,skip,skip,skip,skip,skip
```

### JSON
```json
{
  "exported_at": "2026-06-19T10:35:00Z",
  "config_file": "shownet2026.json",
  "results": [
    {
      "ssid": "shownet-5g",
      "bssid": "11:22:33:44:55:01",
      "tested_at": "2026-06-19T10:30:00Z",
      "assoc": { "status": "pass", "bssid_matched": true },
      "v4_addr": { "status": "pass", "address": "192.168.1.10", "gateway": "192.168.1.1", "dns": ["8.8.8.8"] },
      "v4_gw": { "status": "pass", "rtt_ms": 1.2 },
      "v4_net": { "status": "pass", "rtt_ms": 5.8 },
      "v4_mtu": { "status": "pass", "mtu_bytes": 1500 },
      "v4_dns": { "status": "pass", "resolved": ["142.250.196.100"] },
      "v6_addr": { "status": "pass", "address": "2001:db8::1" },
      "v6_gw": { "status": "pass", "rtt_ms": 1.5 },
      "v6_net": { "status": "pass", "rtt_ms": 6.1 },
      "v6_mtu": { "status": "pass", "mtu_bytes": 1500 },
      "v6_dns": { "status": "pass", "resolved": ["2404:6800:4004:800::2004"] }
    }
  ]
}
```

---

## 9. 配布・署名・権限

- **ターゲット**: macOS 14.0+
- **サンドボックス**: 無効（CoreWLAN association + サブプロセス実行のため）
- **署名**: Developer ID Application証明書
- **ノータリゼーション**: `xcrun notarytool submit` + `xcrun stapler staple`
- **配布**: GitHub Releases（`.dmg`形式）、チーム内Ad Hoc

### 必要なエンタイトルメント

```xml
<!-- MacWifiChecker.entitlements -->
<key>com.apple.developer.networking.wifi-info</key>
<true/>
```

### 位置情報の許可（必須）

macOS はSSID/BSSIDをプライバシー情報として扱うため、CLIツールでは redacted になる。
本アプリは GUI アプリとして以下の対応で制限を回避する：

1. `Info.plist` に `NSLocationWhenInUseUsageDescription` を追加（許可ダイアログの説明文）
2. 起動時に `CLLocationManager.requestWhenInUseAuthorization()` を呼ぶ
3. ユーザーが「許可」すると `CWInterface.ssid()` / `CWInterface.bssid()` が実値を返す

許可拒否の場合はスキャン・接続機能が動作しない旨をアラートで通知し、
システム設定の「プライバシーとセキュリティ > 位置情報サービス」への誘導を表示する。

---

## 10. 未解決事項・注意点

- CoreWLAN の `associate(toNetwork:password:)` はメインスレッドまたは専用スレッドで呼ぶ必要がある場合がある。動作確認が必要。
- macOS 14以降でのWi-Fi association APIの権限挙動（プロファイル有無による差異）を要確認。
- IPv6 DNSサーバーのアドレス取得: RAオプション（RDNSS）をパースするか、`scutil --dns` の出力を利用するか要検討。
- MTU二分探索の実装はping往復が多くなるため、テスト時間とのトレードオフを調整する。
