import SwiftUI
import SwiftData

struct MetricsView: View {
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        MetricsContent(modelContext: modelContext)
        .background(Color(.controlBackgroundColor))
    }
}
