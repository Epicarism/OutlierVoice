# OutlierVoice 🎙️

A multilingual AI voice assistant for iOS with on-device TTS.

## Features

- 🗣️ **Voice Chat** with Claude API
- 🎤 **Speech-to-Text** via WhisperKit (on-device)
- 🔊 **Text-to-Speech** via Kokoro (on-device, 8 languages)
- 🌍 **Multilingual**: 🇺🇸🇬🇧🇯🇵🇨🇳🇪🇸🇫🇷🇮🇹🇧🇷

## Setup

### 1. Clone
```bash
git clone https://github.com/Epicarism/OutlierVoice.git
cd OutlierVoice
```

### 2. Download Models (not in repo - too large)
```bash
# Download Kokoro model (~312MB)
# Place in OutlierVoice/Models/Resources/Models/kokoro-v1_0.safetensors

# Download voices (~50MB total)
# Place in voices/ folder
```

### 3. Open in Xcode
```bash
open OutlierVoice.xcodeproj
```

### 4. Build & Run
- Select your iPhone device
- ⌘R to run

## Dependencies

- [kokoro-ios](https://github.com/Epicarism/kokoro-ios) - Multilingual TTS (forked with eSpeakNG)
- [WhisperKit](https://github.com/argmaxinc/WhisperKit) - On-device STT
- [MLX Swift](https://github.com/ml-explore/mlx-swift) - Apple Silicon ML

## License

MIT
