# Taller Mobile — Flutter

Android app for OBD-II vehicle scanning via Bluetooth Classic (ELM327).

## Prerequisites

- Flutter 3.35+ (or use FVM for version pinning)
- Android Studio with Android SDK
- An Android device or emulator

## Quick Start

```bash
# Install dependencies
flutter pub get

# Run on connected device/emulator
flutter run
```

## Project Structure

```
lib/
├── core/
│   ├── api/          # HTTP client for backend communication
│   ├── bluetooth/    # Bluetooth Classic connection service
│   └── elm327/       # ELM327 protocol handler
├── features/
│   ├── scan/         # Scan screen and logic
│   ├── vehicles/     # Vehicle selection
│   └── history/      # Scan history
├── simulator/        # Mock ELM327 for development
└── main.dart
```

## Simulator Mode

The app includes a mock ELM327 simulator (`lib/simulator/mock_elm327.dart`) for development without physical hardware. Toggle it in settings (Phase 2).
