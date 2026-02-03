import AVFoundation
import KokoroSwift
import MLX
import MLXUtilsLibrary

// MARK: - Comparable Extension
extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// Available Kokoro languages
enum VoiceLanguage: String, CaseIterable, Identifiable {
    case americanEnglish = "a"
    case britishEnglish = "b"
    case japanese = "j"
    case chinese = "z"
    case spanish = "e"
    case french = "f"
    case italian = "i"
    case portuguese = "p"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .americanEnglish: return "🇺🇸 American English"
        case .britishEnglish: return "🇬🇧 British English"
        case .japanese: return "🇯🇵 Japanese"
        case .chinese: return "🇨🇳 Chinese"
        case .spanish: return "🇪🇸 Spanish"
        case .french: return "🇫🇷 French"
        case .italian: return "🇮🇹 Italian"
        case .portuguese: return "🇧🇷 Portuguese"
        }
    }
    
    var flag: String {
        switch self {
        case .americanEnglish: return "🇺🇸"
        case .britishEnglish: return "🇬🇧"
        case .japanese: return "🇯🇵"
        case .chinese: return "🇨🇳"
        case .spanish: return "🇪🇸"
        case .french: return "🇫🇷"
        case .italian: return "🇮🇹"
        case .portuguese: return "🇧🇷"
        }
    }
    
    /// Map to KokoroSwift's Language enum
    /// Now using eSpeakNG for proper multilingual phonemization!
    var kokoroLanguage: Language {
        switch self {
        case .americanEnglish: return .enUS
        case .britishEnglish: return .enGB
        case .japanese: return .japanese
        case .chinese: return .chinese
        case .spanish: return .spanish
        case .french: return .french
        case .italian: return .italian
        case .portuguese: return .portuguese
        }
    }
    
    static var `default`: VoiceLanguage { .americanEnglish }
}

/// Available Kokoro voices
enum KokoroVoice: String, CaseIterable, Identifiable {
    // 🇺🇸 American English (11F, 9M)
    case afHeart = "af_heart"
    case afAlloy = "af_alloy"
    case afAoede = "af_aoede"
    case afBella = "af_bella"
    case afJessica = "af_jessica"
    case afKore = "af_kore"
    case afNicole = "af_nicole"
    case afNova = "af_nova"
    case afRiver = "af_river"
    case afSarah = "af_sarah"
    case afSky = "af_sky"
    case amAdam = "am_adam"
    case amEcho = "am_echo"
    case amEric = "am_eric"
    case amFenrir = "am_fenrir"
    case amLiam = "am_liam"
    case amMichael = "am_michael"
    case amOnyx = "am_onyx"
    case amPuck = "am_puck"
    case amSanta = "am_santa"
    
    // 🇬🇧 British English (4F, 4M)
    case bfAlice = "bf_alice"
    case bfEmma = "bf_emma"
    case bfIsabella = "bf_isabella"
    case bfLily = "bf_lily"
    case bmDaniel = "bm_daniel"
    case bmFable = "bm_fable"
    case bmGeorge = "bm_george"
    case bmLewis = "bm_lewis"
    
    // 🇯🇵 Japanese (4F, 1M)
    case jfAlpha = "jf_alpha"
    case jfGongitsune = "jf_gongitsune"
    case jfNezumi = "jf_nezumi"
    case jfTebukuro = "jf_tebukuro"
    case jmKumo = "jm_kumo"
    
    // 🇨🇳 Chinese Mandarin (4F, 4M)
    case zfXiaobei = "zf_xiaobei"
    case zfXiaoni = "zf_xiaoni"
    case zfXiaoxiao = "zf_xiaoxiao"
    case zfXiaoyi = "zf_xiaoyi"
    case zmYunjian = "zm_yunjian"
    case zmYunxi = "zm_yunxi"
    case zmYunxia = "zm_yunxia"
    case zmYunyang = "zm_yunyang"
    
    // 🇪🇸 Spanish (1F, 2M)
    case efDora = "ef_dora"
    case emAlex = "em_alex"
    case emSanta = "em_santa"
    
    // 🇫🇷 French (1F)
    case ffSiwis = "ff_siwis"
    
    // 🇮🇹 Italian (1F, 1M)
    case ifSara = "if_sara"
    case imNicola = "im_nicola"
    
    // 🇧🇷 Brazilian Portuguese (1F, 2M)
    case pfDora = "pf_dora"
    case pmAlex = "pm_alex"
    case pmSanta = "pm_santa"
    
    var id: String { rawValue }
    
    var language: VoiceLanguage {
        let prefix = rawValue.prefix(1)
        switch prefix {
        case "a": return .americanEnglish
        case "b": return .britishEnglish
        case "j": return .japanese
        case "z": return .chinese
        case "e": return .spanish
        case "f": return .french
        case "i": return .italian
        case "p": return .portuguese
        default: return .americanEnglish
        }
    }
    
    var isFemale: Bool {
        rawValue.contains("f_")
    }
    
    var displayName: String {
        let gender = isFemale ? "♀" : "♂"
        switch self {
        // American English
        case .afHeart: return "Heart \(gender) ❤️"
        case .afAlloy: return "Alloy \(gender)"
        case .afAoede: return "Aoede \(gender)"
        case .afBella: return "Bella \(gender) 🔥"
        case .afJessica: return "Jessica \(gender)"
        case .afKore: return "Kore \(gender)"
        case .afNicole: return "Nicole \(gender) 🎧"
        case .afNova: return "Nova \(gender)"
        case .afRiver: return "River \(gender)"
        case .afSarah: return "Sarah \(gender)"
        case .afSky: return "Sky \(gender)"
        case .amAdam: return "Adam \(gender)"
        case .amEcho: return "Echo \(gender)"
        case .amEric: return "Eric \(gender)"
        case .amFenrir: return "Fenrir \(gender)"
        case .amLiam: return "Liam \(gender)"
        case .amMichael: return "Michael \(gender)"
        case .amOnyx: return "Onyx \(gender)"
        case .amPuck: return "Puck \(gender)"
        case .amSanta: return "Santa \(gender) 🎅"
        // British English
        case .bfAlice: return "Alice \(gender)"
        case .bfEmma: return "Emma \(gender)"
        case .bfIsabella: return "Isabella \(gender)"
        case .bfLily: return "Lily \(gender)"
        case .bmDaniel: return "Daniel \(gender)"
        case .bmFable: return "Fable \(gender)"
        case .bmGeorge: return "George \(gender)"
        case .bmLewis: return "Lewis \(gender)"
        // Japanese
        case .jfAlpha: return "Alpha \(gender)"
        case .jfGongitsune: return "Gongitsune \(gender)"
        case .jfNezumi: return "Nezumi \(gender)"
        case .jfTebukuro: return "Tebukuro \(gender)"
        case .jmKumo: return "Kumo \(gender)"
        // Chinese
        case .zfXiaobei: return "Xiaobei \(gender)"
        case .zfXiaoni: return "Xiaoni \(gender)"
        case .zfXiaoxiao: return "Xiaoxiao \(gender)"
        case .zfXiaoyi: return "Xiaoyi \(gender)"
        case .zmYunjian: return "Yunjian \(gender)"
        case .zmYunxi: return "Yunxi \(gender)"
        case .zmYunxia: return "Yunxia \(gender)"
        case .zmYunyang: return "Yunyang \(gender)"
        // Spanish
        case .efDora: return "Dora \(gender)"
        case .emAlex: return "Alex \(gender)"
        case .emSanta: return "Santa \(gender) 🎅"
        // French
        case .ffSiwis: return "Siwis \(gender)"
        // Italian
        case .ifSara: return "Sara \(gender)"
        case .imNicola: return "Nicola \(gender)"
        // Portuguese
        case .pfDora: return "Dora \(gender)"
        case .pmAlex: return "Alex \(gender)"
        case .pmSanta: return "Santa \(gender) 🎅"
        }
    }
    
    var fileName: String { "\(rawValue).safetensors" }
    
    static var `default`: KokoroVoice { .afHeart }
    
    static func voices(for language: VoiceLanguage) -> [KokoroVoice] {
        allCases.filter { $0.language == language }
    }
    
    static func defaultVoice(for language: VoiceLanguage) -> KokoroVoice {
        voices(for: language).first ?? .default
    }
}

/// Text-to-Speech engine using Kokoro (82M params, ~3.3x realtime on iPhone)
@Observable
@MainActor
final class TTSEngine: NSObject {
    // Kokoro TTS
    private var kokoroEngine: KokoroTTS?
    private var voices: [String: MLXArray] = [:]
    
    // Audio playback
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    
    // Double-buffer pipeline: max 2 chunks in memory
    private var bufferSemaphore: DispatchSemaphore?
    private var pendingBuffers: Int = 0
    
    // System TTS fallback
    private let synthesizer = AVSpeechSynthesizer()
    
    private(set) var isModelLoaded = false
    private(set) var isSpeaking = false
    private(set) var loadingProgress: Double = 0
    
    // Voice settings
    var selectedVoice: KokoroVoice {
        let saved = UserDefaults.standard.string(forKey: "selectedKokoroVoice") ?? KokoroVoice.default.rawValue
        return KokoroVoice(rawValue: saved) ?? .default
    }
    
    var playbackSpeed: Float {
        let saved = UserDefaults.standard.double(forKey: "playbackSpeed")
        let speed = saved > 0 ? saved : 1.0
        return Float(speed.clamped(to: 0.5...2.0))
    }
    
    var useSystemVoice: Bool {
        // Default to system voice (safer, uses less memory)
        // Only use Kokoro if explicitly enabled
        if UserDefaults.standard.object(forKey: "useSystemVoiceFallback") == nil {
            return true  // Default to system voice
        }
        return UserDefaults.standard.bool(forKey: "useSystemVoiceFallback")
    }
    
    // Kokoro outputs at 24kHz
    private let sampleRate: Double = 24000
    
    enum TTSError: LocalizedError {
        case modelNotLoaded
        case voiceNotLoaded(String)
        case generationFailed(String)
        case playbackFailed(String)
        case audioConversionFailed
        
        var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "Kokoro TTS model not loaded"
            case .voiceNotLoaded(let voice):
                return "Voice not loaded: \(voice)"
            case .generationFailed(let reason):
                return "Speech generation failed: \(reason)"
            case .playbackFailed(let reason):
                return "Playback failed: \(reason)"
            case .audioConversionFailed:
                return "Failed to convert audio data"
            }
        }
    }
    
    override init() {
        super.init()
        setupAudioEngine()
    }
    
    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        
        guard let audioEngine = audioEngine,
              let playerNode = playerNode else { return }
        
        audioEngine.attach(playerNode)
    }
    
    /// Load Kokoro model and voices from bundle
    func loadModel(progressHandler: ((Double) -> Void)? = nil) async throws {
        guard !isModelLoaded else { return }
        
        loadingProgress = 0
        progressHandler?(0)
        
        print("[TTS] 🚀 Loading Kokoro TTS model...")
        
        // Find model in bundle
        guard let modelPath = Bundle.main.url(forResource: "kokoro-v1_0", withExtension: "safetensors") else {
            print("[TTS] ❌ Model file not found in bundle, using system voice fallback")
            isModelLoaded = true
            loadingProgress = 1.0
            progressHandler?(1.0)
            return
        }
        
        print("[TTS] 📦 Model found at: \(modelPath.path)")
        
        loadingProgress = 0.3
        progressHandler?(0.3)
        
        do {
            // Initialize Kokoro engine with eSpeakNG for multilingual support
            print("[TTS] 🔧 Initializing KokoroTTS with eSpeakNG (multilingual)...")
            kokoroEngine = KokoroTTS(modelPath: modelPath, g2p: .eSpeakNG)
            print("[TTS] ✅ KokoroTTS initialized with eSpeakNG")
            
            loadingProgress = 0.6
            progressHandler?(0.6)
            
            // Load default voice
            print("[TTS] 🎤 Loading voice: \(selectedVoice.rawValue)...")
            try await loadVoice(selectedVoice)
            
            isModelLoaded = true
            loadingProgress = 1.0
            progressHandler?(1.0)
            print("[TTS] ✅ Kokoro TTS ready!")
        } catch {
            print("[TTS] ❌ Kokoro init failed: \(error)")
            print("[TTS] 🔄 Falling back to system voice")
            kokoroEngine = nil
            isModelLoaded = true
            loadingProgress = 1.0
            progressHandler?(1.0)
        }
    }
    
    /// Load a voice embedding
    func loadVoice(_ voice: KokoroVoice) async throws {
        guard voices[voice.rawValue] == nil else { return }
        
        guard let voicePath = Bundle.main.url(forResource: voice.rawValue, withExtension: "safetensors") else {
            print("[TTS] ⚠️ Voice file not found: \(voice.fileName)")
            throw TTSError.voiceNotLoaded(voice.rawValue)
        }
        
        // Load voice embedding from safetensors
        let voiceData = try MLX.loadArrays(url: voicePath)
        
        // The voice embedding is typically stored under a key like "voice" or the voice name
        if let embedding = voiceData["voice"] ?? voiceData.values.first {
            voices[voice.rawValue] = embedding
            print("[TTS] ✅ Loaded voice: \(voice.displayName)")
        } else {
            throw TTSError.voiceNotLoaded(voice.rawValue)
        }
    }
    
    /// Check if text is valid for TTS processing
    private func isValidForTTS(_ text: String) -> Bool {
        // Must have content
        guard !text.isEmpty else { return false }
        
        // Must have at least some letters (not just punctuation/numbers)
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard letters.count >= 2 else { return false }
        
        // Must not be too short
        guard text.count >= 4 else { return false }
        
        // Check for valid ASCII range mostly
        let asciiCount = text.unicodeScalars.filter { $0.value >= 32 && $0.value <= 126 }.count
        guard Double(asciiCount) / Double(text.count) > 0.5 else { return false }
        
        return true
    }
    
    /// Sanitize text for TTS - remove problematic characters
    private func sanitizeForTTS(_ text: String) -> String {
        var result = text
        
        // Replace newlines with spaces
        result = result.replacingOccurrences(of: "\n", with: " ")
        result = result.replacingOccurrences(of: "\r", with: " ")
        result = result.replacingOccurrences(of: "\t", with: " ")
        
        // Remove code blocks and special markdown
        result = result.replacingOccurrences(of: "```", with: "")
        result = result.replacingOccurrences(of: "`", with: "")
        result = result.replacingOccurrences(of: "**", with: "")
        result = result.replacingOccurrences(of: "__", with: "")
        result = result.replacingOccurrences(of: "##", with: "")
        
        // Remove URLs (they break TTS)
        if let urlRegex = try? NSRegularExpression(pattern: "https?://\\S+", options: .caseInsensitive) {
            result = urlRegex.stringByReplacingMatches(in: result, options: [], range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        
        // Remove emojis and special unicode (keep basic punctuation)
        result = result.unicodeScalars.filter { scalar in
            // Keep ASCII printable characters
            (scalar.value >= 32 && scalar.value <= 126) ||
            // Keep common extended chars (accents, etc)
            (scalar.value >= 192 && scalar.value <= 255)
        }.map { String($0) }.joined()
        
        // Normalize whitespace
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        
        // Trim and cap length
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.count > 500 {
            result = String(result.prefix(500))
        }
        
        return result
    }
    
    /// Split text into chunks that won't exceed token limit
    private func splitIntoChunks(text: String, maxChars: Int) -> [String] {
        // Clean up the text
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If short enough, return as-is
        if cleanText.count <= maxChars {
            return [cleanText]
        }
        
        var chunks: [String] = []
        var currentChunk = ""
        
        // Split by sentences first (., !, ?)
        let sentencePattern = #"[^.!?]+[.!?]+\s*"#
        let regex = try? NSRegularExpression(pattern: sentencePattern, options: [])
        let range = NSRange(cleanText.startIndex..., in: cleanText)
        
        var sentences: [String] = []
        regex?.enumerateMatches(in: cleanText, options: [], range: range) { match, _, _ in
            if let matchRange = match?.range, let swiftRange = Range(matchRange, in: cleanText) {
                sentences.append(String(cleanText[swiftRange]))
            }
        }
        
        // Handle any remaining text without punctuation
        let matchedLength = sentences.joined().count
        if matchedLength < cleanText.count {
            let remaining = String(cleanText.dropFirst(matchedLength))
            if !remaining.trimmingCharacters(in: .whitespaces).isEmpty {
                sentences.append(remaining)
            }
        }
        
        // If no sentences found, split by words
        if sentences.isEmpty {
            sentences = [cleanText]
        }
        
        for sentence in sentences {
            let trimmed = sentence.trimmingCharacters(in: .whitespaces)
            
            // If single sentence is too long, split by commas or words
            if trimmed.count > maxChars {
                let subChunks = splitLongSentence(trimmed, maxChars: maxChars)
                for sub in subChunks {
                    if currentChunk.isEmpty {
                        currentChunk = sub
                    } else if (currentChunk + " " + sub).count <= maxChars {
                        currentChunk += " " + sub
                    } else {
                        chunks.append(currentChunk)
                        currentChunk = sub
                    }
                }
            } else if currentChunk.isEmpty {
                currentChunk = trimmed
            } else if (currentChunk + " " + trimmed).count <= maxChars {
                currentChunk += " " + trimmed
            } else {
                chunks.append(currentChunk)
                currentChunk = trimmed
            }
        }
        
        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }
        
        return chunks.isEmpty ? [cleanText] : chunks
    }
    
    /// Split a long sentence by commas or words
    private func splitLongSentence(_ sentence: String, maxChars: Int) -> [String] {
        // Try splitting by commas first
        let parts = sentence.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        
        var chunks: [String] = []
        var current = ""
        
        for part in parts {
            if part.count > maxChars {
                // Split by words if still too long
                let words = part.components(separatedBy: " ")
                for word in words {
                    if current.isEmpty {
                        current = word
                    } else if (current + " " + word).count <= maxChars {
                        current += " " + word
                    } else {
                        chunks.append(current)
                        current = word
                    }
                }
            } else if current.isEmpty {
                current = part
            } else if (current + ", " + part).count <= maxChars {
                current += ", " + part
            } else {
                chunks.append(current)
                current = part
            }
        }
        
        if !current.isEmpty {
            chunks.append(current)
        }
        
        return chunks
    }
    
    /// Unload model to free memory
    func unloadModel() {
        kokoroEngine = nil
        voices.removeAll()
        isModelLoaded = false
        loadingProgress = 0
        print("[TTS] Model unloaded")
    }
    
    /// Generate speech and play it
    func speakAndPlay(text: String) async throws {
        stopPlayback()
        isSpeaking = true
        
        // Use system voice if user prefers it
        if useSystemVoice {
            print("[TTS] 🔊 Using system voice (user preference)")
            await speakWithSystemVoice(text: text)
            isSpeaking = false
            return
        }
        
        // Lazy load Kokoro if enabled but not loaded
        if !isModelLoaded && !useSystemVoice {
            print("[TTS] 🔄 Lazy loading Kokoro...")
            do {
                try await loadModel()
            } catch {
                print("[TTS] ❌ Kokoro load failed, using system voice: \(error)")
                await speakWithSystemVoice(text: text)
                isSpeaking = false
                return
            }
        }
        
        // Fallback to system if Kokoro still not available
        if kokoroEngine == nil {
            print("[TTS] 🔊 Kokoro not available, using system voice")
            await speakWithSystemVoice(text: text)
            isSpeaking = false
            return
        }
        
        guard let engine = kokoroEngine else {
            throw TTSError.modelNotLoaded
        }
        
        // Ensure voice is loaded
        let voice = selectedVoice
        if voices[voice.rawValue] == nil {
            try await loadVoice(voice)
        }
        
        guard let voiceEmbedding = voices[voice.rawValue] else {
            throw TTSError.voiceNotLoaded(voice.rawValue)
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Split text into smaller chunks - 100 chars max to prevent OOM
        let chunks = splitIntoChunks(text: text, maxChars: 100)
            .map { sanitizeForTTS($0) }
            .filter { isValidForTTS($0) }
        
        guard !chunks.isEmpty else {
            print("[TTS] ⚠️ No valid chunks to speak")
            isSpeaking = false
            return
        }
        
        print("[TTS] 🎙️ Pipeline streaming \(chunks.count) chunk(s)...")
        
        do {
            // Clear memory BEFORE starting
            Memory.clearCache()
            print("[TTS] 🧹 Cleared memory before generation")
            
            // Double-buffer pipeline: generate next while current plays
            // Semaphore limits to 2 chunks in memory max (prevents OOM)
            bufferSemaphore = DispatchSemaphore(value: 2)
            pendingBuffers = 0
            
            // Ensure audio engine is ready
            try setupAudioEngineIfNeeded()
            
            for (index, chunk) in chunks.enumerated() {
                guard isSpeaking else {
                    print("[TTS] ⏹️ Stopped by user")
                    break
                }
                
                // Wait for slot (blocks if 2 buffers already queued)
                bufferSemaphore?.wait()
                pendingBuffers += 1
                
                let chunkPreview = String(chunk.prefix(min(30, chunk.count)))
                print("[TTS] 📝 Generating chunk \(index + 1)/\(chunks.count): \(chunkPreview)...")
                
                // Generate audio with appropriate language
                let genStart = CFAbsoluteTimeGetCurrent()
                let kokoroLanguage = voice.language.kokoroLanguage
                print("[TTS] 🌍 Using language: \(voice.language.displayName) → \(kokoroLanguage)")
                let (samples, _) = try engine.generateAudio(
                    voice: voiceEmbedding,
                    language: kokoroLanguage,
                    text: chunk,
                    speed: playbackSpeed
                )
                let genTime = CFAbsoluteTimeGetCurrent() - genStart
                print("[TTS] ⚡ Generated in \(String(format: "%.2f", genTime))s")
                
                guard isSpeaking else { break }
                
                // Queue buffer (non-blocking! plays while we generate next)
                try queueAudioBuffer(samples: samples, chunkIndex: index)
                
                // Clear generation memory immediately (buffer is copied to audio)
                Memory.clearCache()
            }
            
            // Wait for all queued audio to finish playing
            print("[TTS] ⏳ Waiting for playback to complete...")
            await waitForPlaybackCompletion()
            
            let totalTime = CFAbsoluteTimeGetCurrent() - startTime
            print("[TTS] 🎉 Done! \(String(format: "%.2f", totalTime))s for \(chunks.count) chunks")
            
        } catch {
            isSpeaking = false
            playerNode?.stop()
            Memory.clearCache()
            print("[TTS] ❌ Generation error: \(error)")
            throw TTSError.generationFailed(error.localizedDescription)
        }
        
        Memory.clearCache()
        print("[TTS] 🧹 Final memory clear")
        isSpeaking = false
    }
    
    /// Setup audio engine if needed
    private func setupAudioEngineIfNeeded() throws {
        guard let audioEngine = audioEngine,
              let playerNode = playerNode else {
            throw TTSError.playbackFailed("Audio engine not initialized")
        }
        
        // Stop player first to reset state
        playerNode.stop()
        
        // Configure audio session BEFORE starting engine
        let session = AVAudioSession.sharedInstance()
        // Note: .playback category automatically routes to speaker, no need for .defaultToSpeaker
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setPreferredSampleRate(sampleRate)
        try session.setActive(true, options: [])
        print("[TTS] 🔊 Audio session configured for playback")
        
        // Create audio format (24kHz mono)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw TTSError.audioConversionFailed
        }
        
        // Connect nodes
        audioEngine.disconnectNodeOutput(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
        
        // Always restart engine for clean state
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        try audioEngine.start()
        print("[TTS] ▶️ Audio engine started, isRunning=\(audioEngine.isRunning)")
        
        // Pre-start the player node so it's ready for buffers
        playerNode.play()
        print("[TTS] ▶️ Player node started, isPlaying=\(playerNode.isPlaying)")
    }
    
    /// Queue audio buffer for playback (non-blocking pipeline)
    private func queueAudioBuffer(samples: [Float], chunkIndex: Int) throws {
        guard let playerNode = playerNode else {
            throw TTSError.playbackFailed("Player node not initialized")
        }
        
        // Create audio format (24kHz mono)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw TTSError.audioConversionFailed
        }
        
        // Create buffer
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw TTSError.audioConversionFailed
        }
        
        buffer.frameLength = AVAudioFrameCount(samples.count)
        
        // Copy samples to buffer
        if let channelData = buffer.floatChannelData?[0] {
            samples.withUnsafeBufferPointer { ptr in
                channelData.update(from: ptr.baseAddress!, count: samples.count)
            }
        }
        
        // Schedule buffer WITHOUT .interrupts (queues up, no gaps!)
        // Completion handler releases semaphore slot for next generation
        // IMPORTANT: Signal semaphore IMMEDIATELY (not on MainActor) to avoid deadlock!
        playerNode.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
            // Signal on audio thread immediately - unblocks generation loop
            self?.bufferSemaphore?.signal()
            // Then update UI state on main thread
            Task { @MainActor in
                self?.pendingBuffers -= 1
                print("[TTS] 🔊 Chunk \(chunkIndex + 1) finished playing")
            }
        }
        
        // Start playing if not already
        if !playerNode.isPlaying {
            playerNode.play()
        }
        
        print("[TTS] 📤 Queued chunk \(chunkIndex + 1) (pending: \(pendingBuffers))")
    }
    
    /// Wait for all queued audio to finish
    private func waitForPlaybackCompletion() async {
        // Poll until all buffers are played
        while pendingBuffers > 0 && isSpeaking {
            try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
        }
        playerNode?.stop()
    }
    
    /// Play audio samples (legacy - kept for compatibility)
    private func playAudio(samples: [Float]) async throws {
        try setupAudioEngineIfNeeded()
        try queueAudioBuffer(samples: samples, chunkIndex: 0)
        await waitForPlaybackCompletion()
    }
    
    /// Stop current playback
    func stopPlayback() {
        isSpeaking = false
        playerNode?.stop()
        synthesizer.stopSpeaking(at: .immediate)
    }
    
    // Keep delegate alive
    private var speechDelegate: SpeechDelegate?
    
    /// System voice fallback
    private func speakWithSystemVoice(text: String) async {
        print("[TTS] 🔊 System voice speaking: \(text.prefix(50))...")
        
        let utterance = AVSpeechUtterance(string: text)
        // Use default system voice if Samantha not available
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * playbackSpeed
        utterance.volume = 1.0
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            speechDelegate = SpeechDelegate {
                continuation.resume()
            }
            synthesizer.delegate = speechDelegate
            synthesizer.speak(utterance)
        }
        
        print("[TTS] ✅ System voice finished")
    }
}

// MARK: - Speech Delegate
private class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
    private let onFinish: () -> Void
    
    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        super.init()
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish()
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onFinish()
    }
}
