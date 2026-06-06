# flutter-x-dart-mashup# 🎮 Console — Bluetooth HID Gamepad

Turn your Android phone into a wireless gamepad. Console uses the **Bluetooth HID Device** profile to present itself to any desktop or console as a standard game controller — no drivers, no dongles, no apps on the receiving end.

---

## Features

- **Zero-setup on the host** — pairs like any Bluetooth gamepad; works on Windows, Linux, macOS, Steam Deck, Android TV, and more
- **Dual analog sticks** with smooth deadzone handling
- **D-pad** with diagonal inputs (8 directions)
- **16 buttons** — face buttons (A B X Y), bumpers (LB RB), Select, Start, and more
- **Low-latency reports** — capped at 8 ms send interval with deferred flush
- **Landscape-locked UI** with immersive fullscreen mode
- **Paired device list** — connect to any previously bonded host in one tap

---

## Requirements

| Requirement | Minimum |
|---|---|
| Android version | **9.0 (API 28)** |
| Bluetooth | Hardware HID Device profile support |
| Flutter | **3.18+** |
| Dart SDK | **3.8+** |

> Not all Android 9+ devices support the HID Device profile. Most flagship phones from 2019 onward do. The app checks on launch and shows a message if unsupported.

---

## Getting Started

### 1. Clone and install dependencies

```bash
git clone https://github.com/justwasif/console.git
cd console
flutter pub get
```

### 2. Build and run on your Android device

```bash
flutter run
```

> Make sure USB debugging is enabled and the device is connected.

### 3. Pair your phone to the host machine

1. Tap **Start** in the app — it registers the phone as a HID device
2. On your desktop, open Bluetooth settings and scan for new devices
3. Pair with **"Flutter HID Gamepad"**
4. Back in the app, the paired host will appear in the device list — tap it to connect

---

## Project Structure

```
console/
├── lib/
│   └── main.dart                  # All Flutter UI and gamepad logic
├── android/
│   └── app/src/main/
│       ├── kotlin/.../MainActivity.kt   # Bluetooth HID platform channel
│       └── AndroidManifest.xml          # Bluetooth permissions
├── test/
│   └── widget_test.dart           # D-pad hat switch unit tests
└── pubspec.yaml
```

---

## How It Works

```
Flutter UI (Dart)
      │  MethodChannel "hid_gamepad"
      ▼
MainActivity.kt (Kotlin)
      │  BluetoothProfile.HID_DEVICE
      ▼
Android Bluetooth Stack
      │  BR/EDR
      ▼
Host Machine (sees a standard HID gamepad)
```

The Flutter side handles all UI and translates touch input into a `sendReport` call. The Kotlin side owns the `BluetoothHidDevice` proxy and serialises the 7-byte HID report:

| Byte | Content |
|---|---|
| 0–1 | Button bitmask (16 buttons) |
| 2 | Hat switch (D-pad, 8 directions + neutral) |
| 3 | Left stick X (−127 to 127) |
| 4 | Left stick Y (−127 to 127) |
| 5 | Right stick X (−127 to 127) |
| 6 | Right stick Y (−127 to 127) |

---

## Button Map

| Button | Bit | Label |
|---|---|---|
| A | 0 | South face |
| B | 1 | East face |
| X | 2 | West face |
| Y | 3 | North face |
| LB | 4 | Left bumper |
| RB | 5 | Right bumper |
| — | 6–7 | (reserved) |
| Select | 8 | Center left |
| Start | 9 | Center right |
| — | 10–15 | (reserved / extendable) |

---

## Permissions

The app requests the following at runtime:

| Permission | Why |
|---|---|
| `BLUETOOTH_CONNECT` (API 31+) | Connect to paired devices |
| `BLUETOOTH_SCAN` (API 31+) | List bonded devices |
| `BLUETOOTH_ADVERTISE` (API 31+) | Register as HID device |
| `ACCESS_FINE_LOCATION` (API ≤ 30) | Required for BT device discovery on older Android |

---

## Troubleshooting

**"HID Device profile not ready yet"**
The Bluetooth profile proxy is async. Tap Start again after a moment — it connects within a second or two of app launch.

**Phone doesn't appear in host's Bluetooth scan**
Make sure you tapped Start first. The phone only advertises itself after the HID profile is registered.

**"Pair the desktop first"**
The app connects to already-bonded devices only. Pair once through Android's Bluetooth settings, then use the in-app device list for all future connections.

**Buttons not registering on host**
Some hosts require the gamepad to be the "active" input device. Try pressing a button on the phone while a game or input tester is focused on the host.

**Supported device check fails on my phone**
A small number of Android devices ship without the HID Device profile despite meeting the API level requirement. This is a hardware/firmware limitation and cannot be worked around in software.

---

## Running Tests

```bash
flutter test
```

The test suite covers D-pad hat switch encoding for all 8 directions and neutral.

---

## License

MIT — see `LICENSE` for details.
