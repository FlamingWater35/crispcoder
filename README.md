# CrispCoder 🎬

![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=flat-square&logo=Flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-%230175C2.svg?style=flat-square&logo=dart&logoColor=white)
![FFmpeg](https://img.shields.io/badge/Powered%20By-FFmpeg-%23101416?style=flat-square&logo=ffmpeg&logoColor=white)
![Riverpod](https://img.shields.io/badge/State-Riverpod-%231C2434?style=flat-square&logo=riverpod&logoColor=white)
![Hive](https://img.shields.io/badge/Storage-Hive-%23FF8B24?style=flat-square&logo=hive&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Android-green?style=flat-square)

**CrispCoder** is a modern video transcoder for Android devices, built with Flutter and powered by FFmpeg. It allows queueing multiple video encoding tasks, configuring advanced transcode presets, burning in subtitles, trimming video durations, visually cropping aspect ratios, extracting audio/subtitles, and managing hardware/software encoding preferences—all while running reliably in the background.

<div align="center">
  <a href="https://github.com/FlamingWater35/crispcoder/releases/latest">
    <img src="https://img.shields.io/badge/Download-Latest_Release-2196F3?style=for-the-badge&logo=github&logoColor=white" alt="Download Latest Release">
  </a>
</div>

---

## 📷 Screenshots

<div align="center">
  <table>
    <tr>
      <td align="center"><img src="assets\screenshots\Screenshot 2026-07-02 094656.png" width="250px" alt="Video Options"><br><sub>Video Options</sub></td>
      <td align="center"><img src="assets\screenshots\Screenshot 2026-07-02 094834.png" width="250px" alt="Quick Options"><br><sub>Quick Options</sub></td>
      <td align="center"><img src="assets\screenshots\Screenshot 2026-07-02 094737.png" width="250px" alt="Visual Crop Editor"><br><sub>Visual Crop Editor</sub></td>
      <td align="center"><img src="assets\screenshots\Screenshot 2026-07-02 094616.png" width="250px" alt="Settings Screen"><br><sub>Settings Screen</sub></td>
    </tr>
  </table>
</div>

---

## ✨ Features

- **🎬 Advanced Transcoding Engine**
  - Powered by `ffmpeg`.
  - Hardware (`h264_mediacodec`, `hevc_mediacodec`) and Software (`libx264`, `libx265`, `libvpx-vp9`) encoding support.
  - Hardware-accelerated decoding (`-hwaccel mediacodec`) for optimized processing speed.
  - Configurable software encoder presets (`ultrafast` to `slow`) to balance speed and compression.
  - Multi-threaded software encoding optimized for modern multi-core CPUs.
  - Rate control via Constant Rate Factor (CRF) or target Bitrate.

- **📋 Queue Management**
  - Concurrent background queue processing.
  - Crash recovery: queue state is persisted locally and restored on app restart.
  - Live progress updates (Percentage, FPS, Speed, ETA, Bitrate).
  - Interactive notifications with a "Cancel" action button and grouped completion alerts.

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

## 📲 Download & Installation

1. Click the **Download Latest Release** button above, or go to the [Releases page](https://github.com/FlamingWater35/crispcoder/releases/latest).
2. Download the `crispcoder-vX.X.X-arm64-v8a.apk` file corresponding to your device architecture (usually `arm64-v8a` for modern devices).
3. Open the downloaded file on your Android device. You may need to allow "Install from unknown sources" in your settings.
4. Once installed, open CrispCoder and grant the necessary storage and notification permissions.

*Note: You can also check for updates directly within the app from the Settings screen.*

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
│   └── services/                 # External APIs (FFmpeg, Permissions, Device Info, Notifications)
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
