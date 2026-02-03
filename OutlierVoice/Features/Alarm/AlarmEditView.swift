import SwiftUI

struct AlarmEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var alarmManager = AlarmManager.shared
    
    // Form state
    @State private var time: Date
    @State private var title: String
    @State private var message: String
    @State private var repeatDays: Set<Int>
    @State private var requiresMath: Bool
    @State private var mathDifficulty: ClaudeAlarm.MathDifficulty
    @State private var selectedPreset: Int = 0
    
    let existingAlarm: ClaudeAlarm?
    
    init(existingAlarm: ClaudeAlarm? = nil) {
        self.existingAlarm = existingAlarm
        
        if let alarm = existingAlarm {
            _time = State(initialValue: alarm.time)
            _title = State(initialValue: alarm.title)
            _message = State(initialValue: alarm.message)
            _repeatDays = State(initialValue: alarm.repeatDays)
            _requiresMath = State(initialValue: alarm.requiresMathToSnooze)
            _mathDifficulty = State(initialValue: alarm.mathDifficulty)
        } else {
            _time = State(initialValue: Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date())
            _title = State(initialValue: "Wake Up!")
            _message = State(initialValue: "Good morning! Time to start your day!")
            _repeatDays = State(initialValue: [])
            _requiresMath = State(initialValue: false)
            _mathDifficulty = State(initialValue: .medium)
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Time Picker
                Section {
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                }
                
                // Repeat Days
                Section("Repeat") {
                    DayPicker(selectedDays: $repeatDays)
                }
                
                // Message Presets
                Section("What Claude Says") {
                    Picker("Preset", selection: $selectedPreset) {
                        ForEach(0..<ClaudeAlarm.presetMessages.count, id: \.self) { index in
                            Text(ClaudeAlarm.presetMessages[index].title)
                                .tag(index)
                        }
                    }
                    .onChange(of: selectedPreset) { _, newValue in
                        let preset = ClaudeAlarm.presetMessages[newValue]
                        title = preset.title
                        if !preset.message.isEmpty {
                            message = preset.message
                        }
                    }
                    
                    TextField("Title", text: $title)
                    
                    TextField("Message", text: $message, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                // Math Challenge
                Section {
                    Toggle("Require Math to Snooze", isOn: $requiresMath)
                    
                    if requiresMath {
                        Picker("Difficulty", selection: $mathDifficulty) {
                            ForEach(ClaudeAlarm.MathDifficulty.allCases, id: \.self) { diff in
                                Text(diff.displayName).tag(diff)
                            }
                        }
                        
                        // Preview
                        let preview = mathDifficulty.generateProblem()
                        HStack {
                            Text("Example:")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(preview.question)
                                .font(.headline)
                        }
                    }
                } header: {
                    Text("Anti-Snooze")
                } footer: {
                    Text("Solve a math problem to snooze. Can't just tap and go back to sleep!")
                }
                
                // Delete button for existing alarms
                if existingAlarm != nil {
                    Section {
                        Button(role: .destructive) {
                            if let alarm = existingAlarm {
                                alarmManager.deleteAlarm(alarm)
                            }
                            dismiss()
                        } label: {
                            HStack {
                                Spacer()
                                Text("Delete Alarm")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(existingAlarm == nil ? "New Alarm" : "Edit Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveAlarm()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private func saveAlarm() {
        let alarm = ClaudeAlarm(
            id: existingAlarm?.id ?? UUID(),
            title: title,
            message: message,
            time: time,
            repeatDays: repeatDays,
            isEnabled: true,
            voiceId: existingAlarm?.voiceId ?? "af_heart",
            language: existingAlarm?.language ?? "enUS",
            requiresMathToSnooze: requiresMath,
            mathDifficulty: mathDifficulty
        )
        
        if existingAlarm != nil {
            alarmManager.updateAlarm(alarm)
        } else {
            alarmManager.addAlarm(alarm)
        }
    }
}

struct DayPicker: View {
    @Binding var selectedDays: Set<Int>
    
    let days = [
        (1, "S"), (2, "M"), (3, "T"), (4, "W"),
        (5, "T"), (6, "F"), (7, "S")
    ]
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(days, id: \.0) { day, label in
                Button {
                    if selectedDays.contains(day) {
                        selectedDays.remove(day)
                    } else {
                        selectedDays.insert(day)
                    }
                } label: {
                    Text(label)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(selectedDays.contains(day) ? Color.accentColor : Color(.systemGray5))
                        )
                        .foregroundStyle(selectedDays.contains(day) ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

#Preview {
    AlarmEditView()
}
