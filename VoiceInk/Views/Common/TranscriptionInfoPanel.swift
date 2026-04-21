import SwiftUI

/// Reusable component that displays transcription details.
/// Used in both the inline history sliding panel and the separate history window's metadata view.
struct TranscriptionInfoPanel: View {
    let transcription: Transcription

    var body: some View {
        Form {
            detailsSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Details Section

    private var detailsSection: some View {
        Section {
            metadataRow(
                icon: "calendar",
                label: "Date",
                value: transcription.timestamp.formatted(date: .abbreviated, time: .shortened)
            )

            metadataRow(
                icon: "hourglass",
                label: "Duration",
                value: transcription.duration.formatTiming()
            )

            if let modelName = transcription.transcriptionModelName {
                metadataRow(
                    icon: "cpu.fill",
                    label: "Transcription Model",
                    value: modelName
                )

                if let duration = transcription.transcriptionDuration {
                    metadataRow(
                        icon: "clock.fill",
                        label: "Transcription Time",
                        value: duration.formatTiming()
                    )
                }
            }

            if let powerModeValue = powerModeDisplay(
                name: transcription.powerModeName,
                emoji: transcription.powerModeEmoji
            ) {
                metadataRow(
                    icon: "bolt.fill",
                    label: "Power Mode",
                    value: powerModeValue
                )
            }
        } header: {
            Text("Details")
        }
    }

    private func metadataRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 20, height: 20)

            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            Spacer(minLength: 0)

            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
    }

    private func powerModeDisplay(name: String?, emoji: String?) -> String? {
        guard name != nil || emoji != nil else { return nil }

        switch (emoji?.trimmingCharacters(in: .whitespacesAndNewlines), name?.trimmingCharacters(in: .whitespacesAndNewlines)) {
        case let (.some(emojiValue), .some(nameValue)) where !emojiValue.isEmpty && !nameValue.isEmpty:
            return "\(emojiValue) \(nameValue)"
        case let (.some(emojiValue), _) where !emojiValue.isEmpty:
            return emojiValue
        case let (_, .some(nameValue)) where !nameValue.isEmpty:
            return nameValue
        default:
            return nil
        }
    }
}
