// Halcyon - home screen widgets for iPhone, iPad and Mac.
//
// Symbian widget code can't run on the iOS home screen (WidgetKit shows snapshots
// drawn by this extension and the emulator can't run in the background), so these
// are native widgets in a Belle-inspired style. Taps open Symbian apps through the
// halcyon:// deep link.
//
// Licensed under the GNU General Public License v3 or later.

import WidgetKit
import SwiftUI
import AppIntents

@main
struct HalcyonWidgets: WidgetBundle {
    var body: some Widget {
        PhoneClockWidget()
        SymbianAppWidget()
        DockAppsWidget()
        #if os(iOS)
        OpenSymbianAppControl()
        #endif
    }
}

// MARK: - Shared look

private struct WidgetBackground: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.20, green: 0.17, blue: 0.48),
                                Color(red: 0.16, green: 0.36, blue: 0.62),
                                Color(red: 0.27, green: 0.66, blue: 0.62)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private struct WidgetAppIcon: View {
    let uid: UInt32?
    let name: String
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(LinearGradient(colors: [.white, Color(white: 0.9)], startPoint: .top, endPoint: .bottom))
            if let uid, let image = SharedStore.loadIcon(uid: uid) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(size * 0.12)
            } else {
                Text(String(name.prefix(1)))
                    .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                    .foregroundStyle(.gray)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }
}

// MARK: - Clock (analog face + date, like the phone's clock widget)

struct PhoneClockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PhoneClock", provider: MinuteProvider()) { entry in
            PhoneClockView(date: entry.date)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("Phone Clock")
        .description("An analog clock and the date.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct MinuteEntry: TimelineEntry {
    let date: Date
}

struct MinuteProvider: TimelineProvider {
    func placeholder(in context: Context) -> MinuteEntry { MinuteEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (MinuteEntry) -> Void) {
        completion(MinuteEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MinuteEntry>) -> Void) {
        let start = Calendar.current.dateInterval(of: .minute, for: .now)?.start ?? .now
        let entries = (0..<60).map { MinuteEntry(date: start.addingTimeInterval(Double($0) * 60)) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct PhoneClockView: View {
    @Environment(\.widgetFamily) private var family
    let date: Date

    var body: some View {
        HStack(spacing: 16) {
            AnalogFace(date: date)
                .frame(maxWidth: 120, maxHeight: 120)
            if family == .systemMedium {
                VStack(alignment: .leading, spacing: 4) {
                    Text(date, format: .dateTime.hour().minute())
                        .font(.system(size: 40, weight: .thin, design: .rounded))
                    Text(date, format: .dateTime.weekday(.wide))
                        .font(.headline)
                    Text(date, format: .dateTime.day().month(.wide))
                        .font(.subheadline)
                        .opacity(0.85)
                }
                .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
        }
    }
}

private struct AnalogFace: View {
    let date: Date

    var body: some View {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minute = Double(components.minute ?? 0)
        let hour = Double((components.hour ?? 0) % 12) + minute / 60
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                Circle().fill(.white.opacity(0.95))
                Circle().strokeBorder(Color(white: 0.75), lineWidth: side * 0.03)
                ForEach(0..<12, id: \.self) { tick in
                    Capsule()
                        .fill(Color(white: tick % 3 == 0 ? 0.25 : 0.6))
                        .frame(width: side * (tick % 3 == 0 ? 0.035 : 0.02), height: side * 0.09)
                        .offset(y: -side * 0.38)
                        .rotationEffect(.degrees(Double(tick) * 30))
                }
                Hand(length: side * 0.26, width: side * 0.05, color: Color(white: 0.2))
                    .rotationEffect(.degrees(hour * 30))
                Hand(length: side * 0.37, width: side * 0.035, color: Color(white: 0.3))
                    .rotationEffect(.degrees(minute * 6))
                Circle().fill(Color(red: 0.85, green: 0.25, blue: 0.2)).frame(width: side * 0.07)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private struct Hand: View {
        let length: CGFloat
        let width: CGFloat
        let color: Color

        var body: some View {
            Capsule()
                .fill(color)
                .frame(width: width, height: length)
                .offset(y: -length / 2)
        }
    }
}

// MARK: - One Symbian app

struct SymbianAppWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SymbianApp", intent: SelectSymbianAppIntent.self, provider: AppProvider()) { entry in
            SymbianAppWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("Symbian App")
        .description("Opens a Symbian app in one tap.")
        .supportedFamilies([.systemSmall])
    }
}

struct AppEntry: TimelineEntry {
    let date: Date
    let app: SymbianAppEntity?
}

struct AppProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> AppEntry { AppEntry(date: .now, app: nil) }

    func snapshot(for configuration: SelectSymbianAppIntent, in context: Context) async -> AppEntry {
        AppEntry(date: .now, app: configuration.app ?? SharedStore.loadApps().first.map(SymbianAppEntity.init))
    }

    func timeline(for configuration: SelectSymbianAppIntent, in context: Context) async -> Timeline<AppEntry> {
        Timeline(entries: [AppEntry(date: .now, app: configuration.app)], policy: .never)
    }
}

struct SymbianAppWidgetView: View {
    let entry: AppEntry

    var body: some View {
        if let app = entry.app {
            VStack(spacing: 10) {
                WidgetAppIcon(uid: app.uid, name: app.name, size: 64)
                Text(app.name)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .widgetURL(app.uid.map { DeepLink.launch(uid: $0).url })
        } else {
            Text("Edit the widget to choose an app.")
                .font(.footnote)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Dock apps (four icons)

struct DockAppsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DockApps", provider: DockProvider()) { entry in
            DockAppsView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("Phone Dock")
        .description("The apps in your phone's dock.")
        .supportedFamilies([.systemMedium])
    }
}

struct DockEntry: TimelineEntry {
    let date: Date
    let apps: [SymbianApp]
}

struct DockProvider: TimelineProvider {
    func placeholder(in context: Context) -> DockEntry { DockEntry(date: .now, apps: []) }

    func getSnapshot(in context: Context, completion: @escaping (DockEntry) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DockEntry>) -> Void) {
        completion(Timeline(entries: [load()], policy: .after(.now.addingTimeInterval(3600))))
    }

    private func load() -> DockEntry {
        let apps = SharedStore.loadApps()
        let layout = SharedStore.loadLayout()
        var uids = layout?.dock ?? []
        if uids.isEmpty { uids = Array((layout?.pages.first ?? []).prefix(4)) }
        let chosen = uids.compactMap { uid in apps.first { $0.uid == uid } }
        return DockEntry(date: .now, apps: Array(chosen.prefix(4)))
    }
}

struct DockAppsView: View {
    let entry: DockEntry

    var body: some View {
        if entry.apps.isEmpty {
            Text("Open \(AppConfig.displayName) to set up your phone.")
                .font(.footnote)
                .foregroundStyle(.white)
        } else {
            HStack(spacing: 0) {
                ForEach(entry.apps) { app in
                    Link(destination: DeepLink.url(for: app)) {
                        VStack(spacing: 6) {
                            WidgetAppIcon(uid: app.uid, name: app.name, size: 54)
                            Text(app.name)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

// MARK: - Control Center / Lock Screen / Action button (iOS 18)

#if os(iOS)
struct OpenSymbianAppControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "OpenSymbianApp", provider: ControlAppProvider()) { value in
            ControlWidgetButton(action: OpenSymbianAppIntent(app: value)) {
                Label(value.name, systemImage: "app.badge")
            }
        }
        .displayName("Open Symbian App")
        .description("Opens a Symbian app in the emulator.")
    }
}

struct SelectSymbianControlIntent: ControlConfigurationIntent {
    static var title: LocalizedStringResource = "Choose App"

    @Parameter(title: "App")
    var app: SymbianAppEntity?

    init() {}
}

struct ControlAppProvider: AppIntentControlValueProvider {
    func previewValue(configuration: SelectSymbianControlIntent) -> SymbianAppEntity {
        configuration.app ?? SymbianAppEntity(app: SymbianApp(uid: 0, name: "Symbian App"))
    }

    func currentValue(configuration: SelectSymbianControlIntent) async throws -> SymbianAppEntity {
        configuration.app ?? SharedStore.loadApps().first.map(SymbianAppEntity.init)
            ?? SymbianAppEntity(app: SymbianApp(uid: 0, name: "Symbian App"))
    }
}
#endif
