import AppKit
import SwiftUI

@main
enum Main {
    static func main() {
        let args = CommandLine.arguments
        if Treadmill.debug { setvbuf(stdout, nil, _IOLBF, 0) }
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            let page: Page = args.contains("--settings") ? .settings : .main
            MainActor.assumeIsolated { Snapshot.render(to: args[i + 1], page: page) }
            return
        }
        TreadmillBarApp.main()
    }
}

struct TreadmillBarApp: App {
    @State private var treadmill = Treadmill()

    var body: some Scene {
        MenuBarExtra {
            PanelView(treadmill: treadmill)
        } label: {
            MenuBarLabel(treadmill: treadmill)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
enum Snapshot {
    static func render(to path: String, page: Page) {
        _ = NSApplication.shared
        let storeURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("snapshot-sessions.json")
        try? FileManager.default.removeItem(at: storeURL)
        let store = SessionStore(url: storeURL)
        let profile = Profile(defaults: UserDefaults(suiteName: "TreadmillBarSnapshot")!)
        profile.weight = 72
        profile.height = 175
        profile.age = 35
        profile.sex = .male
        profile.stepSource = .model
        profile.stepFactor = 1
        let t = Treadmill(sessions: store, profile: profile, startBluetooth: false)
        t.linkState = .connected
        t.deviceName = "HS–750WP"
        t.hasControl = true
        t.message = "Set speed: OK"
        t.sample = Sample(status: 3, speed: 2.6, time: 3492, distance: 1958, kcal: 137.8, steps: 2975)
        t.target = 3.0
        t.cadence = 76
        let now = Date()
        t.speedHistory = (0 ..< 300).map { i in
            let speed: Double = i < 60 ? 1.0 + Double(i) / 40 : (i < 200 ? 2.6 : 3.0)
            return SpeedPoint(date: now.addingTimeInterval(Double(i - 300) * 2), speed: speed)
        }
        store.update(with: t.sample!, at: now, weight: profile.weight, height: profile.height)

        let view = PanelView(treadmill: t, page: page)
            .background(Color(red: 0.16, green: 0.16, blue: 0.18))
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: view)
        host.frame.size = host.fittingSize
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .windowBackgroundColor
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("snapshot \(Int(host.bounds.width))x\(Int(host.bounds.height)) -> \(path)")
    }
}
