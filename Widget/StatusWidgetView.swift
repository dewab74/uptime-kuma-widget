import KumaKit
import KumaUI
import SwiftUI
import WidgetKit

struct StatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StatusEntry

    var body: some View {
        let content = WidgetContent(
            state: entry.state, configured: entry.configured, date: entry.date, staleLimit: entry.staleLimit,
            size: size)
        content
            .containerBackground(for: .widget) {
                WidgetBackground(status: content.backgroundStatus)
            }
            .widgetURL(URL(string: "kumastatus://open"))
    }

    private var size: WidgetSize {
        switch family {
        case .systemSmall: .small
        case .systemMedium: .medium
        default: .large
        }
    }
}

#Preview("Small", as: .systemSmall) {
    KumaStatusWidget()
} timeline: {
    StatusEntry.preview
}

#Preview("Medium", as: .systemMedium) {
    KumaStatusWidget()
} timeline: {
    StatusEntry.preview
}

#Preview("Large", as: .systemLarge) {
    KumaStatusWidget()
} timeline: {
    StatusEntry.preview
}
