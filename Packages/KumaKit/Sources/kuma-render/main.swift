import AppKit
import KumaKit
import KumaUI
import SwiftUI

// Renders every widget size, light and dark, to PNG, from a live status page
// or from sample data. For checking layout and for README screenshots:
//
//   swift run --package-path Packages/KumaKit kuma-render [--hide up,...] [--insecure] <out-dir> [url [slug]]
//
// --hide lists the statuses to leave out, as the app's Display settings do:
// up, pending, maintenance, unknown. --insecure skips certificate checks, as
// turning off Verify TLS certificate does.

var arguments = Array(CommandLine.arguments.dropFirst())
var options = DisplayOptions.default
let insecure = arguments.contains("--insecure")
arguments.removeAll { $0 == "--insecure" }
if let flag = arguments.firstIndex(of: "--hide"), flag + 1 < arguments.count {
    let names = arguments[flag + 1].split(separator: ",").map { $0.lowercased() }
    let byName = Dictionary(uniqueKeysWithValues: MonitorStatus.allCases.map { ($0.label.lowercased(), $0) })
        .merging(["unknown": .unknown, "nodata": .unknown]) { first, _ in first }
    options = DisplayOptions(hiddenStatuses: Set(names.compactMap { byName[$0] }))
    arguments.removeSubrange(flag...(flag + 1))
}
guard let output = arguments.first.map({ URL(fileURLWithPath: $0) }) else {
    FileHandle.standardError.write(
        Data("usage: kuma-render [--hide up,pending,...] [--insecure] <out-dir> [url [slug]]\n".utf8))
    exit(2)
}

var state = SharedState(snapshot: SampleData.snapshot())
if arguments.count >= 2 {
    let rest = Array(arguments.dropFirst())
    let configuration: KumaConfiguration
    do {
        configuration = try KumaConfiguration.parse(
            address: rest[0], slug: rest.count > 1 ? rest[1] : "", verifyCertificate: !insecure)
    } catch {
        FileHandle.standardError.write(Data("\(error.errorDescription ?? "invalid URL")\n".utf8))
        exit(2)
    }
    do {
        state = SharedState(snapshot: try await StatusPageClient().fetch(configuration))
    } catch {
        FileHandle.standardError.write(Data("fetch failed: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let rendered = await MainActor.run { () -> [String] in
    var names: [String] = []
    for size in WidgetSize.allCases {
        for scheme in [ColorScheme.light, .dark] {
            let content = WidgetContent(
                state: state, configured: true, date: .now, staleLimit: 300, size: size, options: options)
            let view =
                content
                .padding(16)
                .frame(width: size.pointSize.width, height: size.pointSize.height)
                .background(WidgetBackground(status: content.backgroundStatus))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(20)
                .background(scheme == .dark ? Color(white: 0.12) : Color(white: 0.86))
                .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.cgImage,
                let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            else { continue }
            let name = "widget-\(size)-\(scheme == .dark ? "dark" : "light").png"
            try? png.write(to: output.appending(path: name))
            names.append(name)
        }
    }
    return names
}
print("Wrote \(rendered.joined(separator: ", ")) to \(output.path)")
