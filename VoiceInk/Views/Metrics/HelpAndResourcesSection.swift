import SwiftUI

struct HelpAndResourcesSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Why VoiceWink Exists")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.primary.opacity(0.8))

            VStack(alignment: .leading, spacing: 12) {
                Text("VoiceWink is a fork of VoiceInk for environments with stricter security requirements.")
                    .font(.system(size: 13, weight: .semibold))

                Text("It keeps the core dictation experience, runs transcription locally, and removes anything this fork does not need.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)

                Text("If VoiceInk works for your setup, please support it by purchasing a license there. If you use VoiceWink because you need a more locked-down option, consider supporting VoiceInk anyway. VoiceInk helps fund the work this fork builds on.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)

                resourceLink(
                    icon: "heart.fill",
                    title: "Support VoiceInk",
                    url: "https://tryvoiceink.com"
                )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
    
    private func resourceLink(icon: String, title: String, url: String? = nil) -> some View {
        Button(action: {
            if let urlString = url, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.accentColor)
                    .frame(width: 20)
                
                Text(title)
                    .font(.system(size: 13))
                    .fontWeight(.semibold)
                
                Spacer()
                
                Image(systemName: "arrow.up.right")
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

        }
        .buttonStyle(.plain)
    }
}
