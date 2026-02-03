import Foundation

/// A scheduled Claude alarm call
struct ClaudeAlarm: Identifiable, Codable {
    let id: UUID
    var title: String
    var message: String  // What Claude says when calling
    var time: Date       // When to trigger
    var repeatDays: Set<Int>  // 1=Sun, 2=Mon, etc. Empty = one-time
    var isEnabled: Bool
    var voiceId: String  // Which Kokoro voice to use
    var language: String // Language code
    var requiresMathToSnooze: Bool
    var mathDifficulty: MathDifficulty
    
    enum MathDifficulty: String, Codable, CaseIterable {
        case easy = "easy"      // 12 + 7 = ?
        case medium = "medium"  // 17 × 8 = ?
        case hard = "hard"      // 23 × 17 = ?
        
        var displayName: String {
            switch self {
            case .easy: return "Easy (Addition)"
            case .medium: return "Medium (Multiplication)"
            case .hard: return "Hard (Big Multiplication)"
            }
        }
        
        func generateProblem() -> (question: String, answer: Int) {
            switch self {
            case .easy:
                let a = Int.random(in: 5...20)
                let b = Int.random(in: 5...20)
                return ("\(a) + \(b) = ?", a + b)
            case .medium:
                let a = Int.random(in: 6...15)
                let b = Int.random(in: 3...9)
                return ("\(a) × \(b) = ?", a * b)
            case .hard:
                let a = Int.random(in: 12...25)
                let b = Int.random(in: 11...19)
                return ("\(a) × \(b) = ?", a * b)
            }
        }
    }
    
    init(
        id: UUID = UUID(),
        title: String = "Wake Up!",
        message: String = "Good morning! Time to start your day. Remember: you can do hard things!",
        time: Date = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date(),
        repeatDays: Set<Int> = [],
        isEnabled: Bool = true,
        voiceId: String = "af_heart",
        language: String = "enUS",
        requiresMathToSnooze: Bool = false,
        mathDifficulty: MathDifficulty = .medium
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.time = time
        self.repeatDays = repeatDays
        self.isEnabled = isEnabled
        self.voiceId = voiceId
        self.language = language
        self.requiresMathToSnooze = requiresMathToSnooze
        self.mathDifficulty = mathDifficulty
    }
    
    var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: time)
    }
    
    var repeatDescription: String {
        if repeatDays.isEmpty {
            return "One time"
        }
        let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let sorted = repeatDays.sorted()
        if sorted == [2, 3, 4, 5, 6] {
            return "Weekdays"
        } else if sorted == [1, 7] {
            return "Weekends"
        } else if sorted == Array(1...7) {
            return "Every day"
        }
        return sorted.map { days[$0 - 1] }.joined(separator: ", ")
    }
}
