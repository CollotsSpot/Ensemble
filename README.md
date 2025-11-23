# Amass

A minimalistic Flutter mobile client for [Music Assistant](https://music-assistant.io/) - stream your entire music library from your Music Assistant server to your mobile device.

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

## Getting Started

### Prerequisites

- Flutter SDK (>=3.0.0)
- Dart SDK
- Android Studio / Xcode for mobile development

### Download APK

Download the latest APK from [GitHub Actions](https://github.com/CollotsSpot/Amass/actions) artifacts (look for the "amass-apk" artifact in successful builds).

### Build from Source

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

4. Run the app
```bash
flutter run
```

Or build an APK:
```bash
flutter build apk --release
```
The APK will be available at `build/app/outputs/flutter-apk/app-release.apk`

### Setup

1. Launch the app
2. Navigate to the **Library** tab
3. Tap **Configure Server** or go to **Settings**
4. Enter your Music Assistant server URL (e.g., `music.serverscloud.org` or `192.168.1.100`)
5. Tap **Connect**
6. Browse your library and start playing music!

## Requirements

- Music Assistant server (v2.7.0 or later recommended)
- Network connectivity to your Music Assistant server
- Android device (API 21+) or iOS device

## Architecture

- **lib/main.dart** - App entry point with multi-provider setup
- **lib/screens/** - UI screens (Player, Library, Settings, Album Details)
- **lib/widgets/** - Reusable UI components (Player controls, Progress bar, etc.)
- **lib/models/** - Data models (MediaItem, Artist, Album, Track, AudioTrack)
- **lib/services/** - Business logic (MusicAssistantAPI, AudioPlayerService, SettingsService)
- **lib/providers/** - State management (MusicPlayerProvider, MusicAssistantProvider)

## Key Technologies

- **Flutter** - Cross-platform mobile framework
- **just_audio** - Audio playback
- **audio_service** - Background audio support
- **web_socket_channel** - WebSocket communication with Music Assistant server
- **provider** - State management
- **shared_preferences** - Local settings storage

## Music Assistant API

The app communicates with Music Assistant using:
- WebSocket connection on port 8095
- JSON-RPC style message protocol
- HTTP streaming endpoints for audio playback
- Support for browsing library and searching content

## License

MIT License
