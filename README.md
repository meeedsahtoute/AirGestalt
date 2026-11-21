# AirGestalt (Acoustic Systems Architecture)

> **Flagship, open-source iOS SwiftUI architecture bringing clone and third-party earbuds (Airoha, BES, Huilian, Bluetrum, Qualcomm) as close to native Apple AirPods Pro 2/3 as physically and programmatically possible.**
> Target: iOS 17.0 – iOS 27.2.1 • Non-jailbroken execution via **LiveContainer** & **SideStore** / **AltStore**.

---

## 🎧 Table of Contents
1. [Core Architectural Overview](#-core-architectural-overview)
2. [Reverse-Engineered Continuity Protocol (0x004C)](#-reverse-engineered-continuity-protocol-0x004c)
3. [Hardware Clone ANC Unlocker & RACE Protocol](#-hardware-clone-anc-unlocker--race-protocol)
4. [SIMD-Accelerated (vDSP) Hybrid Audio Engine](#-simd-accelerated-vdsp-hybrid-audio-engine)
5. [Studio-Grade Microphone & Voice Isolation](#-studio-grade-microphone--voice-isolation)
6. [Live GATT Diffing Lab & Profile Exporter](#-live-gatt-diffing-lab--profile-exporter)
7. [Installation: LiveContainer vs. SideStore](#-installation-livecontainer-vs-sidestore)
8. [GestaltX iOS 27.x Synergy Guide](#-gestaltx-ios-27x-synergy-guide)
9. [Zero-Mac CI/CD Pipeline](#-zero-mac-cicd-pipeline)

---

## 🏛 Core Architectural Overview

AirGestalt bridges the gap between third-party Bluetooth hardware and Apple's closed audio ecosystem through three foundational pillars:
- **RF & Protocol Emulation:** Parses raw Apple Continuity proximity pairing advertisements (`0x004C`, Type `0x07`) with little-endian bitfield extraction and fallback to GATT Battery Service (`0x180F`).
- **Low-Level Hardware Control:** Interacts with proprietary chipset vendor GATT channels (Airoha RACE, Nordic UART / Bluetrum, Bestechnic TOTA) to command hardware Active Noise Cancellation, Transparency, and Hardware EQ.
- **Real-Time SIMD Audio DSP:** Leverages Apple's `Accelerate` (`vDSP`) framework on a unified, zero-downgrade `AVAudioEngine` pipeline to synthesize real-time anti-noise, measure acoustic Bluetooth latency via cross-correlation, and isolate speech without degrading A2DP audio bandwidth.

```
                              ┌──────────────────────────────────┐
                              │     AirGestalt iOS Frontend      │
                              │ (SwiftUI + SceneKit 3D + Island) │
                              └─────────────────┬────────────────┘
                                                │
                 ┌──────────────────────────────┴──────────────────────────────┐
                 │                                                             │
                 ▼                                                             ▼
   ┌───────────────────────────┐                                 ┌───────────────────────────┐
   │    CoreBluetooth Engine   │                                 │   Shared AVAudioEngine    │
   ├───────────────────────────┤                                 ├───────────────────────────┤
   │ • ContinuityDecoder       │                                 │ • Zero-Downgrade A2DP     │
   │   (0x004C Type 0x07 EMA)  │                                 │   (.playAndRecord)        │
   │ • CloneGATTClient         │                                 │ • VDSPAntiNoiseProcessor  │
   │   (RACE / NUS / BES TOTA) │                                 │   (NLMS + Biquad + VAD)   │
   │ • PacketDiffEngine        │                                 │ • AutoLatencyCalibrator   │
   │   (Stem-press Diff Lab)   │                                 │   (vDSP_conv Log-Chirp)   │
   └─────────────┬─────────────┘                                 │ • ProMicEngine (HW Voice) │
                 │                                               └─────────────┬─────────────┘
                 ▼                                                             ▼
   ┌───────────────────────────┐                                 ┌───────────────────────────┐
   │   Earbud RF / BLE GATT    │                                 │ iPhone Mic & A2DP Earbuds │
   └───────────────────────────┘                                 └───────────────────────────┘
```

---

## 📡 Reverse-Engineered Continuity Protocol (`0x004C`)

Apple devices broadcast proximity pairing frames inside BLE advertisement manufacturer data (`CBAdvertisementDataManufacturerDataKey`). AirGestalt tracks these packets continuously with Background State Restoration (`CBCentralManagerOptionRestoreIdentifierKey`).

### 27-Byte Continuity Frame Specification

| Byte Offset | Field Name | Description & Bitfield Layout |
|:---|:---|:---|
| `0x00` – `0x01` | **Company ID** | `0x4C, 0x00` (Apple Inc., Little-Endian `0x004C`) |
| `0x02` | **Type** | `0x07` (Proximity Pairing Message) |
| `0x03` – `0x04` | **Device Model** | Model Identifier (Little-Endian UInt16):<br>• `0x0220`: AirPods 1<br>• `0x0F20`: AirPods 2<br>• `0x1320`: AirPods 3<br>• `0x1920`: AirPods 4 (Active ANC)<br>• `0x0E20`: AirPods Pro 1<br>• `0x1420` / `0x2420`: AirPods Pro 2<br>• `0x2720`: AirPods Pro 3<br>• `0x0A20` / `0x1F20`: AirPods Max |
| `0x05` | **Status** | • **Bit 5 (`0x20`)**: Flip Flag (Swaps Left/Right assignment)<br>• **Bits 1 & 3**: In-Ear Detection (Left & Right)<br>• **Bit 0 / 2**: Primary Active Microphone |
| `0x06` | **Earbud Battery** | • **High Nibble**: Left Earbud (0–10 in 10% steps; `0xF` = Disconnected)<br>• **Low Nibble**: Right Earbud (0–10 in 10% steps; `0xF` = Disconnected) |
| `0x07` | **Case & Charging** | • **Low Nibble (Bits 0–3)**: Case Battery (0–10 in 10% steps)<br>• **Bit 4 (`0x10`)**: Left Earbud Charging<br>• **Bit 5 (`0x20`)**: Right Earbud Charging<br>• **Bit 6 (`0x40`)**: Case Charging |
| `0x08` | **Lid Open Count** | 8-bit counter incrementing each time the case is physically opened |

### Exponential Moving Average (EMA) Proximity Gate
To prevent distant earbuds from triggering spurious pairing pop-ups, raw RSSI is filtered via:
$$\text{RSSI}_{\text{smoothed}} = \alpha \cdot \text{RSSI}_{\text{current}} + (1 - \alpha) \cdot \text{RSSI}_{\text{previous}} \quad (\alpha = 0.28)$$
The pairing sheet is triggered **only** when $\text{RSSI}_{\text{smoothed}} \ge -62\text{ dBm}$ **and** `lidOpenCount` increments.

### Seamless Background Fallback
When iOS suppresses `0x004C` beacons in suspended states, AirGestalt automatically transitions to the standard BLE GATT Battery Service (`0x180F` / Characteristic `0x2A19`), polling battery percentages directly.

---

## ⚡ Hardware Clone ANC Unlocker & RACE Protocol

Third-party clone earbuds feature specialized DSP chips. AirGestalt maintains a separate BLE GATT connection alongside standard A2DP audio.

### Supported Vendor Services & UUIDs
- **Airoha RACE (Remote Access Control):** Service `5052494D-2DAB-0341-6972-6F6861424C45`, Sony Variant `DC405470-A351-4A59-97D8-2E2E3B207FBB`.
- **Bluetrum / Nordic UART (NUS):** Service `6E400001-B5A3-F393-E0A9-E50E24DCCA9E` (TX: `0002`, RX: `0003`).
- **Bestechnic (BES) DataPath TOTA:** Service `0000FE01-0000-1000-8000-00805F9B34FB`.
- **Huilian Starlink:** Service `0000FD00-0000-1000-8000-00805F9B34FB`.

### 6-Byte Airoha RACE Packet Framing
```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|       Sync Byte (0x05)        |       Sync Byte (0x5A)        |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|       Length LSB (UInt16)     |       Length MSB (UInt16)     |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|       Opcode LSB (UInt16)     |       Opcode MSB (UInt16)     |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                       Payload Data ...                        |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

### Safety Lock against Hardware Bricking
> [!CAUTION]
> Clone chipsets risk permanent flash corruption if vendor OTA commands are dispatched inadvertently. AirGestalt implements a hardware safety lock that strictly intercepts and halts destructive opcodes:
> - `0x1681`: Flash / RAM Write
> - `0x1600`: FOTA Initialization
> - `0x1682`: NVRAM Sector Write
> - `0x1683`: Sector Erase

---

## 🎛 SIMD-Accelerated (`vDSP`) Hybrid Audio Engine

### Zero-Downgrade A2DP Routing
By default, standard iOS `.playAndRecord` sessions demote Bluetooth connections to 8kHz/16kHz Hands-Free Profile (HFP). AirGestalt configures `AVAudioSession`:
```swift
try session.setCategory(.playAndRecord, mode: .measurement, options: [.allowBluetoothA2DP, .defaultToSpeaker])
try session.setPreferredInput(builtInMic)
```
Excluding `.allowBluetooth` forces the operating system to keep the A2DP SBC/AAC stereo sink operating at 48kHz / 16-bit fidelity while utilizing the iPhone's multi-mic array for acoustic reference.

### 1. SIMD Adaptive NLMS Anti-Noise Filter
- **Rumble Cut Filter:** Cascaded 2nd-order Biquad IIR filter (`vDSP_biquad`) isolates the 35Hz–550Hz acoustic window.
- **Adaptive NLMS Equation:**
  $$y(n) = \mathbf{w}^T(n) \mathbf{x}(n) = \sum_{k=0}^{L-1} w_k(n) x(n-k) \quad \text{via } \texttt{vDSP\_dotpr}$$
  $$e(n) = d(n) - y(n)$$
  $$\mathbf{w}(n+1) = \mathbf{w}(n) + \frac{\mu}{\epsilon + \|\mathbf{x}(n)\|^2} e(n) \mathbf{x}(n) \quad \text{via } \texttt{vDSP\_vsma}$$
- **Destructive Inversion:** Generates anti-phase acoustic cancellation via `vDSP_vneg`.

### 2. Automatic Bluetooth Latency Calibration (`AutoLatencyCalibrator.swift`)
Measures exact round-trip A2DP latency in under 3 seconds:
1. Synthesizes a 60ms logarithmic chirp ($120\text{ Hz} \to 4500\text{ Hz}$).
2. Captures room acoustic reflection via the iPhone's microphone.
3. Computes 1D cross-correlation via `vDSP_conv`:
   $$R_{xy}[n] = \sum_{m} x[m] y[m+n]$$
4. Detects the maximum peak with `vDSP_maxvi`, locks the delay ring buffer (typically $40\text{ ms} - 160\text{ ms}$), and enables manual phase offset adjustments ($\pm 40\text{ ms}$).

### 3. Spectral-Matched Psychoacoustic Masking
- Runs real-time FFT via `vDSP_DFT` ($N = 512$).
- Computes real-time SPL ($\text{dB}$) and ambient noise contours.
- Dynamically generates pink/brown noise curves matching the room's noise floor to mask speech chatter without acoustic fatigue.

### 4. Conversation Awareness (Real-Time VAD)
- Integrates energy in human voice frequencies ($300\text{ Hz} - 3400\text{ Hz}$).
- Smoothly ducks anti-noise and masking by $-18\text{ dB}$ over $150\text{ ms}$ upon detecting speech.
- Automatically restores full noise cancellation after 4 seconds of silence.

---

## 🎙 Studio-Grade Microphone & Voice Isolation

Overcomes low-quality clone microphone hardware by transforming vocal capture into broadcast-grade audio:
- **Apple Hardware Voice Processing:** `inputNode.setVoiceProcessingEnabled(true)` with AGC active.
- **Sub-Bass Rumble Cut:** High-pass filter at 85Hz ($12\text{ dB/octave}$).
- **vDSP Adaptive Noise Gate:** Soft RMS attack ($80\text{ ms}$) and release ($20\text{ ms}$) to silence background room hiss.
- **Warmth & Presence EQ:** $+2.5\text{ dB}$ presence boost at $3.2\text{ kHz}$ ($Q = 1.2$) and a gentle $-2.2\text{ dB}$ notch at $7.2\text{ kHz}$ for de-essing.
- **Broadcast Compressor:** $-18\text{ dB}$ threshold, $2:1$ ratio, $+3.2\text{ dB}$ makeup gain.
- **10-Second Comparison Recorder:** A/B toggle between DSP ON and raw capture with direct `.m4a` export.

---

## 🧪 Live GATT Diffing Lab & Profile Exporter

Reverse-engineer unmapped earbuds directly in the app:
1. Navigate to the **GATT Lab** tab.
2. Tap **Record Diff**.
3. Squeeze or tap the earbud stem to switch modes (ANC $\leftrightarrow$ Transparency).
4. Tap **Stop & Diff**: Changed bytes are highlighted in orange and green.
5. Tap **Export Profile JSON** to copy a structured community profile ready for a GitHub PR:

```json
{
  "ancOffHex" : "055A0400060A0001",
  "ancOnHex" : "055A0400060A0101",
  "chipset" : "AB1562A",
  "name" : "AB1562A Profile",
  "notifyCharUUID" : "4E4F5449-2DAB-0341-6972-6F6861424C45",
  "serviceUUID" : "5052494D-2DAB-0341-6972-6F6861424C45",
  "transparencyHex" : "055A0400060A0201",
  "vendor" : "Airoha (MediaTek)",
  "writeCharUUID" : "52414345-2DAB-0341-6972-6F6861424C45"
}
```

---

## 📲 Installation: LiveContainer vs. SideStore

AirGestalt provides two distinct target builds:

```
                              ┌──────────────────────────────────┐
                              │     Dual-Target Distribution     │
                              └─────────────────┬────────────────┘
                                                │
                 ┌──────────────────────────────┴──────────────────────────────┐
                 │                                                             │
                 ▼                                                             ▼
   ┌───────────────────────────┐                                 ┌───────────────────────────┐
   │ AirGestalt-LiveContainer  │                                 │   AirGestalt-SideStore    │
   ├───────────────────────────┤                                 ├───────────────────────────┤
   │ Target: AirGestaltCore    │                                 │ Target: AirGestaltFull    │
   │ Standalone application    │                                 │ Includes Dynamic Island   │
   │ No App Extensions         │                                 │ ActivityKit Extensions    │
   │ Ideal for LiveContainer   │                                 │ Ideal for SideStore,      │
   │ without signing limits    │                                 │ AltStore, or TrollStore   │
   └───────────────────────────┘                                 └───────────────────────────┘
```

### Option A: LiveContainer (Recommended for unlimited sideloading)
1. Download `AirGestalt-LiveContainer.ipa` from the GitHub Release.
2. Open **LiveContainer**, tap **+**, and select the downloaded IPA.
3. Launch AirGestalt directly inside the LiveContainer sandbox.

### Option B: SideStore / AltStore (For Dynamic Island Live Activities)
1. Download `AirGestalt-SideStore.ipa`.
2. Open **SideStore**, tap **My Apps**, tap **+**, and select the IPA.
3. SideStore signs both the main app and the `AirGestaltWidget` extension to enable Dynamic Island live battery rings and mode controls.

---

## 🔮 GestaltX iOS 27.x Synergy Guide

AirGestalt is built to harmonize with future iOS systems and the GestaltX specification:
- **Dynamic Island Integration:** Interactive `AppIntent` buttons for instant ANC mode changes without opening the app.
- **AcousticID Continuity:** Emulates hardware identity markers across iOS audio accessories.
- **Audio Intelligence Hand-off:** Coordinates seamlessly with system-wide voice transcription and spatial tracking.

---

## 🚀 Zero-Mac CI/CD Pipeline

The project includes a complete zero-Mac automation pipeline:
- `project.yml`: Structured for [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate `.xcodeproj` deterministically.
- `.github/workflows/build-ipa.yml`: Builds release binaries for both targets using `CODE_SIGNING_ALLOWED=NO`, packages them into `.ipa` archives, and generates automated GitHub Releases.

To generate the Xcode project locally:
```bash
xcodegen generate
```

---

## 📄 License
AirGestalt is licensed under the **MIT License**.
