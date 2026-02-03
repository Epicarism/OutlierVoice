import SwiftUI

struct AlarmListView: View {
    @State private var alarmManager = AlarmManager.shared
    @State private var showingAddAlarm = false
    @State private var editingAlarm: ClaudeAlarm?
    
    var body: some View {
        NavigationStack {
            List {
                if alarmManager.alarms.isEmpty {
                    ContentUnavailableView {
                        Label("No Alarms", systemImage: "alarm")
                    } description: {
                        Text("Schedule Claude to call you!")
                    } actions: {
                        Button("Add Alarm") {
                            showingAddAlarm = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    ForEach(alarmManager.alarms) { alarm in
                        AlarmRow(alarm: alarm) {
                            alarmManager.toggleAlarm(alarm)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingAlarm = alarm
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            alarmManager.deleteAlarm(alarmManager.alarms[index])
                        }
                    }
                }
            }
            .navigationTitle("🔔 Claude Alarms")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddAlarm = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddAlarm) {
                AlarmEditView()
            }
            .sheet(item: $editingAlarm) { alarm in
                AlarmEditView(existingAlarm: alarm)
            }
        }
    }
}

struct AlarmRow: View {
    let alarm: ClaudeAlarm
    let onToggle: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(alarm.timeString)
                    .font(.system(size: 42, weight: .light, design: .rounded))
                    .foregroundStyle(alarm.isEnabled ? .primary : .secondary)
                
                Text(alarm.title)
                    .font(.headline)
                    .foregroundStyle(alarm.isEnabled ? .primary : .secondary)
                
                HStack(spacing: 8) {
                    Text(alarm.repeatDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if alarm.requiresMathToSnooze {
                        Label("Math", systemImage: "function")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { alarm.isEnabled },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    AlarmListView()
}
