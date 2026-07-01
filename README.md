# CrispCoder 🎬

![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-%230175C2.svg?style=for-the-badge&logo=dart&logoColor=white)
![FFmpeg](https://img.shields.io/badge/Powered%20By-FFmpeg-%23101416?style=for-the-badge&logo=ffmpeg&logoColor=white)
![Riverpod](https://img.shields.io/badge/State-Riverpod-%231C2434?style=for-the-badge&logo=riverpod&logoColor=white)
![Hive](https://img.shields.io/badge/Storage-Hive-%23FF8B24?style=for-the-badge&logo=hive&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Android-green?style=for-the-badge)

**CrispCoder** is a modern video transcoder for Android devices, built with Flutter and powered by FFmpeg. It allows queueing multiple video encoding tasks, configuring advanced transcode presets, burning in subtitles, trimming video durations, and managing hardware/software encoding preferences—all while running reliably in the background.

---

## ✨ Features

- **🎬 Advanced Transcoding Engine**
  - Powered by `ffmpeg`.
  - Hardware (`h264_mediacodec`, `hevc_mediacodec`) and Software (`libx264`, `libx265`) encoding support.
  - Rate control via Constant Rate Factor (CRF) or target Bitrate.

- **📋 Queue Management**
  - Concurrent background queue processing.
  - Crash recovery: queue state is persisted locally and restored on app restart.
  - Live progress updates (Percentage, FPS, Speed, ETA, Bitrate).

- **✂️ Editing & Customization**
  - Trim video start and end times.
  - Hardcode (burn-in) subtitle tracks directly into the video.
  - Remove audio tracks entirely.
  - Customize resolution, framerate, video/audio codecs, and output container (MP4, MKV, WebM).

- **⚙️ User Preferences**
  - Global encoder preference (Auto, Hardware, Software) configurable in Settings.
  - Theme mode selection (System, Light, Dark).
  - Persistent notification control for background processing.

- **🛡️ Robust Architecture**
  - **State Management:** Riverpod (`flutter_riverpod`).
  - **Local Storage:** Hive CE for persisting queue, history, presets, and app settings.
  - **Background Execution:** Foreground service with wakelock support for uninterrupted long encodes.

---

## 📱 Usage Guide

1. **Select a Video**: Tap "New Encode" and choose a video file from your device.
2. **Choose a Preset**: Select from built-in Handbrake-style presets or configure a "Custom" profile.
3. **Edit (Optional)**:
   - Trim the video by setting start and end times (`HH:MM:SS`).
   - Select a subtitle track to burn into the video.
   - Toggle "Remove Audio" to mute the output.
4. **Configure Output**: Adjust video codec, resolution, framerate, and container format.
5. **Start Encoding**: Hit "Start Encode". The task will be added to the queue and begin processing. You can navigate away, and the foreground service will keep it alive.
6. **Review**: Once completed, the output video is automatically saved to your device's gallery. You can view past encodes in the Logs tab.

---

## 🚀 Building From Source

### Prerequisites

- Flutter SDK
- Dart SDK
- Android Studio (for running on physical devices or emulators)

### Installation

1. **Clone the repository:**

   ```bash
   git clone https://github.com/FlamingWater35/crispcoder.git
   cd crispcoder
   ```

2. **Install dependencies:**

   ```bash
   flutter pub get
   ```

3. **Run the app:**

   ```bash
   flutter run
   ```

---

## 📂 Project Structure

```text
lib/
├── app.dart                      # Root MaterialApp & Theme configuration
├── main.dart                     # Entry point, Hive initialization, Bootstrap
├── core/
│   ├── constants/                # App constants (Hive box names, default presets)
│   ├── errors/                   # Custom exception definitions
│   └── utils/                    # Helpers (Path sanitization, FFmpeg parsing, Snackbars)
├── data/
│   ├── models/                   # Data models (EncodeTask, MediaInfo, TranscodePreset)
│   ├── repositories/             # Hive-backed data stores (Queue, Presets, Settings)
│   └── services/                 # External APIs (FFmpeg, Permissions, Device Info)
├── features/
│   ├── editor/                   # UI for configuring a new encode task
│   ├── home/                     # Queue screen and queue tile widgets
│   ├── logs/                     # Internal log viewer
│   ├── preview/                  # Video preview player
│   └── settings/                 # App settings (Theme, Encoder, Permissions)
└── providers/                    # Riverpod notifiers for state management
```

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE.md) file for details.
