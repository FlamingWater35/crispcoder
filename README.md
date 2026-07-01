# CrispCoder 🎬

![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-%230175C2.svg?style=for-the-badge&logo=dart&logoColor=white)
![FFmpeg](https://img.shields.io/badge/Powered%20By-FFmpeg-%23101416?style=for-the-badge&logo=ffmpeg&logoColor=white)
![Riverpod](https://img.shields.io/badge/State-Riverpod-%231C2434?style=for-the-badge&logo=riverpod&logoColor=white)
![Hive](https://img.shields.io/badge/Storage-Hive-%23FF8B24?style=for-the-badge&logo=hive&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Android-green?style=for-the-badge)

**CrispCoder** is a modern video transcoder for Android devices, built with Flutter and powered by FFmpeg. It allows queueing multiple video encoding tasks, configuring advanced transcode presets, burning in subtitles, trimming video durations, visually cropping aspect ratios, and managing hardware/software encoding preferences—all while running reliably in the background.

---

## ✨ Features

- **🎬 Advanced Transcoding Engine**
  - Powered by `ffmpeg`.
  - Hardware (`h264_mediacodec`, `hevc_mediacodec`) and Software (`libx264`, `libx265`) encoding support.
  - Hardware-accelerated decoding (`-hwaccel mediacodec`) for optimized processing speed.
  - Configurable software encoder presets (`ultrafast` to `slow`) to balance speed and compression.
  - Multi-threaded software encoding optimized for modern multi-core CPUs.
  - Rate control via Constant Rate Factor (CRF) or target Bitrate.

- **📋 Queue Management**
  - Concurrent background queue processing.
  - Crash recovery: queue state is persisted locally and restored on app restart.
  - Live progress updates (Percentage, FPS, Speed, ETA, Bitrate).

- **✂️ Editing & Customization**
  - Trim video start and end times visually or manually (`HH:MM:SS`).
  - Visual Crop Editor: Drag and resize a bounding box directly on the video frame to set custom aspect ratios.
  - Hardcode (burn-in) subtitle tracks directly into the video.
  - Extract audio or subtitle tracks independently without processing the video.
  - Remove audio tracks entirely.
  - Customize resolution, framerate, video/audio codecs, and output container (MP4, MKV, WebM).

- **⚙️ User Preferences**
  - Global encoder preference (Auto, Hardware, Software) configurable in Settings.
  - Theme mode selection (System, Light, Dark).
  - Persistent notification control for background processing.
  - Custom output directory configuration.

---

## 📱 Usage Guide

1. **Select Output Mode**: Choose whether to encode a Video, extract Audio, or extract Subtitles.
2. **Select a Video**: Tap the source picker and choose a video file from your device.
3. **Choose a Preset**: Select from built-in Handbrake-style presets or configure a "Custom" profile.
4. **Edit (Optional)**:
   - **Trim**: Set start and end times visually or via text input.
   - **Crop**: Use the visual crop editor to drag, resize, and center a selection box for custom aspect ratios.
   - **Subtitles**: Select a subtitle track to burn into the video (or extract as `.srt`).
   - **Audio**: Toggle "Remove Audio" to mute the output.
5. **Configure Output**: Adjust video codec, resolution, framerate, encoder speed, and container format.
6. **Start Encoding**: Hit "Start Encode". The task will be added to the queue and begin processing. You can navigate away, and the foreground service will keep it alive.
7. **Review**: Once completed, the output file is automatically saved to your device's gallery or specified directory. You can view past encodes in the Logs tab.

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
│   ├── preview/                  # Video preview player & visual editors
│   └── settings/                 # App settings (Theme, Encoder, Permissions)
└── providers/                    # Riverpod notifiers for state management
```

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE.md) file for details.
