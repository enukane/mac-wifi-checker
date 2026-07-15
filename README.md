# Mac Wi-Fi Checker

Mac Wi-Fi Checker is a macOS app for validating Wi-Fi access points (APs) by BSSID.  
It scans nearby APs, connects to selected APs one by one, runs IPv4/IPv6 connectivity checks, and exports results as CSV/JSON.

## Features

- Scan APs (SSID/BSSID/Band/RSSI)
- Select APs manually or via config-based auto-select rules
- Sequential AP validation with 11 checks:
  - Assoc
  - v4 Addr / v4 GW / v4 Net / v4 MTU / v4 DNS
  - v6 Addr / v6 GW / v6 Net / v6 MTU / v6 DNS
- Export results to CSV or JSON
- Save/load JSON config files

## Requirements

- macOS 14+
- Xcode 15+
- Location permission enabled for the app (required to access SSID/BSSID)

## Project Structure

- `MacWifiChecker/` – app source (SwiftUI app, models, services, view models, views)
- `MacWifiCheckerTests/` – unit tests
- `project.yml` – XcodeGen spec

## Build

This repository includes both `project.yml` and `MacWifiChecker.xcodeproj`.

If you want to regenerate the project file:

```bash
xcodegen generate
```

Build with Xcode or:

```bash
xcodebuild -project MacWifiChecker.xcodeproj -scheme MacWifiChecker -configuration Debug build
```

## Test

```bash
xcodebuild -project MacWifiChecker.xcodeproj -scheme MacWifiCheckerTests test
```

## Config File Format

Example:

```json
{
  "passphrase": "shownet2026",
  "ipv4_ping_target": "1.1.1.1",
  "ipv6_ping_target": "2606:4700:4700::1111",
  "dns_lookup_target": "www.google.com",
  "auto_select": {
    "ssids": ["shownet-5g"],
    "bssids": ["11:22:33:44:55:01"]
  },
  "ssid_psk_overrides": {
    "shownet-staff": "staffpass2026"
  }
}
```

## Notes

- The app is intended for operational Wi-Fi validation environments where switching AP connections during testing is acceptable.
- For local/dev builds in this repository, code signing and hardened runtime are configured to ease local execution.
