<div align="center">
  <img src="assets/images/amass-main-logo.png" alt="Amass Logo" height="120">
  <h1>Amass</h1>
  <p>A minimalistic mobile client for <a href="https://music-assistant.io/">Music Assistant</a></p>
  <p>Stream your entire music library from your Music Assistant server to your mobile device.</p>
</div>

---

## Features

### Music Assistant Integration
- **Server Connection** - Connect to your Music Assistant server via WebSocket
- **Library Browsing** - Browse artists, albums, and tracks from your server
- **Album Details** - View album information and track listings
- **Music Streaming** - Stream audio directly from your Music Assistant server
- **Auto-Reconnect** - Automatic reconnection with connection status monitoring
- **Settings Management** - Configure server URL with persistent storage

### Player Features
- Clean, minimalistic dark UI design
- Full audio playback controls (play/pause/skip/seek)
- Progress bar with time display
- Volume control slider
- Now playing display with track information
- Background audio playback support
- Queue management

## Download

Download the latest APK from [GitHub Actions](https://github.com/CollotsSpot/Amass/actions) - look for the "amass-apk" artifact in successful builds.

## Setup

1. Launch the app
2. Navigate to the **Library** tab
3. Tap **Configure Server** or go to **Settings**
4. Enter your Music Assistant server URL (e.g., `music.serverscloud.org` or `192.168.1.100`)
5. Tap **Connect**
6. Browse your library and start playing music!

## Requirements

- Music Assistant server (v2.7.0 or later recommended)
- Network connectivity to your Music Assistant server
- Android device (Android 5.0+)

## About Music Assistant

Amass is a client for [Music Assistant](https://music-assistant.io/), an open-source music library manager and player that integrates with various music sources and streaming providers. You'll need a running Music Assistant server to use this app.

Learn more: [music-assistant.io](https://music-assistant.io/)

## License

MIT License

---

## For Developers

<details>
<summary>Build from Source</summary>

### Prerequisites
- Flutter SDK (>=3.0.0)
- Dart SDK

### Build Instructions

1. Clone the repository
```bash
git clone https://github.com/CollotsSpot/Amass.git
cd Amass
```

2. Install dependencies
```bash
flutter pub get
```

3. Generate launcher icons
```bash
flutter pub run flutter_launcher_icons
```

4. Build APK
```bash
flutter build apk --release
```

The APK will be available at `build/app/outputs/flutter-apk/app-release.apk`

</details>

<details>
<summary>Technologies Used</summary>

- **Flutter** - Cross-platform mobile framework
- **just_audio** - Audio playback
- **audio_service** - Background audio support
- **web_socket_channel** - WebSocket communication
- **provider** - State management
- **shared_preferences** - Local settings storage

</details>
