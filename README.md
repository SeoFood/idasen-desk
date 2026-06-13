# Idasen Desk

Native macOS menu bar controller for IKEA IDASEN / Linak desks.

## Requirements

- macOS 14 or newer
- Xcode 26.5 or newer
- Swift 6
- XcodeGen for regenerating `IdasenDesk.xcodeproj`

## Build

```sh
xcodegen generate
xcodebuild -scheme IdasenDesk -destination 'platform=macOS' build
```

## Scope

This is a greenfield SwiftUI app. It does not migrate preferences or code from the
legacy [`idasen-desk-controller-mac`](https://github.com/DWilliames/idasen-desk-controller-mac)
app. That project is only used as a behavioral
reference for the IDASEN Bluetooth protocol and AppleScript compatibility.
