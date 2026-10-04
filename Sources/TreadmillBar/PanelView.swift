import Charts
import ServiceManagement
import SwiftUI

struct MenuBarLabel: View {
    let treadmill: Treadmill

    var body: some View {
        if let s = treadmill.sample, s.time > 0 {
            Text("👣 \(Format.steps(treadmill.displaySteps ?? s.steps)) · \(Format.time(s.time))")
                .monospacedDigit()
        } else {
            Image(systemName: treadmill.isConnected ? "figure.walk" : "figure.stand")
        }
    }
}

enum Page { case main, settings }

struct PanelView: View {
    let treadmill: Treadmill
    @State private var page: Page

    init(treadmill: Treadmill, page: Page = .main) {
        self.treadmill = treadmill
        _page = State(initialValue: page)
    }

    var body: some View {
        Group {
            switch page {
            case .main:
                MainPage(treadmill: treadmill) { new in
                    withAnimation(.snappy) { page = new }
                }
            case .settings:
                SettingsPage(treadmill: treadmill) {
                    withAnimation(.snappy) { page = .main }
                }
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}

private struct MainPage: View {
    let treadmill: Treadmill
    let open: (Page) -> Void
    @State private var sliderValue = 3.0
    @State private var editingSlider = false

    private var s: Sample? { treadmill.sample }
    private var profile: Profile { treadmill.profile }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            speedSection
            controls
            Divider()
            stats
            if treadmill.speedHistory.count > 1 { chart }
            Divider()
            today
            footer
        }
        .onChange(of: treadmill.target ?? s?.speed ?? 0) { _, new in
            if !editingSlider { sliderValue = new }
        }
    }

    private var statusColor: Color {
        guard treadmill.isConnected, let s else { return .secondary }
        switch s.status {
        case FitShow.running: return .green
        case 5, 6: return .red
        default: return .orange
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            Text(treadmill.isConnected ? (s.map { FitShow.statusName($0.status) } ?? "Connected") : treadmill.message)
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(treadmill.deviceName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Image(systemName: treadmill.isConnected ? "dot.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                .foregroundStyle(treadmill.isConnected ? Color.accentColor : .secondary)
                .font(.caption)
        }
    }

    private var speedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.1f", s?.speed ?? 0))
                    .font(.system(size: 46, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: s?.speed)
                Text("km/h").foregroundStyle(.secondary)
                Spacer()
                if let target = treadmill.target {
                    Label(String(format: "%.1f", target), systemImage: "arrow.right")
                        .font(.title3.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.accentColor)
                        .transition(.opacity)
                }
            }

            HStack(spacing: 8) {
                Button { treadmill.nudge(-0.1) } label: { Image(systemName: "minus") }
                Slider(value: $sliderValue, in: treadmill.speedMin ... treadmill.speedMax) { editing in
                    editingSlider = editing
                    if !editing { treadmill.setSpeed(sliderValue) }
                }
                Button { treadmill.nudge(0.1) } label: { Image(systemName: "plus") }
            }
            .controlSize(.small)

            HStack(spacing: 6) {
                ForEach([2, 3, 4, 5, 6], id: \.self) { v in
                    Button("\(v)") { treadmill.setSpeed(Double(v)) }
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .disabled(!treadmill.isRunning)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                controlButton("Start", "play.fill", .green) { treadmill.start() }
                controlButton("Pause", "pause.fill", .orange) { treadmill.pause() }
                controlButton("Stop", "stop.fill", .red) { treadmill.stop() }
            }
            .disabled(!treadmill.isConnected)
            if !treadmill.message.isEmpty && treadmill.isConnected {
                Text(treadmill.message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func controlButton(_ title: String, _ icon: String, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .controlSize(.large)
    }

    private var stats: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 12) {
            GridRow {
                Stat(title: "Steps", icon: "shoeprints.fill", value: treadmill.displaySteps.map(Format.steps),
                     detail: profile.usesStepModel ? s.map { "treadmill: \(Format.steps($0.steps))" } : nil)
                Stat(title: "Time", icon: "timer", value: s.map { Format.time($0.time) })
            }
            GridRow {
                Stat(title: "Distance", icon: "point.topleft.down.to.point.bottomright.curvepath",
                     value: s.map { String(format: "%.2f km", Double($0.distance) / 1000) })
                Stat(title: "Calories", icon: "flame.fill", value: calories.value, detail: calories.detail)
            }
            GridRow {
                Stat(title: "Cadence", icon: "metronome.fill",
                     value: treadmill.displayCadence.map { String(format: "%.0f spm", $0) })
                Stat(title: "Pace", icon: "speedometer", value: s.map { "\(Format.pace($0.speed)) /km" })
            }
            GridRow {
                Stat(title: "Burn rate", icon: "bolt.heart.fill", value: burnRate)
                Stat(title: "Intensity", icon: "gauge.with.dots.needle.33percent",
                     value: s.map { String(format: "%.1f MET", Energy.met(speed: $0.speed)) })
            }
        }
    }

    private var calories: (value: String?, detail: String?) {
        guard let s else { return (nil, nil) }
        guard profile.hasWeight else { return (String(format: "%.0f kcal", s.kcal), "from treadmill") }
        let active = Energy.active(distance: s.distance, weight: profile.weight)
        let detail = profile.bmrPerDay.map {
            String(format: "active · +%.0f resting", Energy.resting(seconds: s.time, bmrPerDay: $0))
        } ?? "active"
        return (String(format: "%.0f kcal", active), detail)
    }

    private var burnRate: String? {
        guard let s, profile.hasWeight else { return nil }
        return String(format: "%.0f kcal/h", Energy.activePerHour(speed: s.speed, weight: profile.weight))
    }

    private var chart: some View {
        Chart(treadmill.speedHistory) { p in
            AreaMark(x: .value("Time", p.date), y: .value("km/h", p.speed))
                .interpolationMethod(.stepEnd)
                .foregroundStyle(.linearGradient(colors: [.green.opacity(0.35), .green.opacity(0.02)],
                                                 startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("Time", p.date), y: .value("km/h", p.speed))
                .interpolationMethod(.stepEnd)
                .foregroundStyle(.green)
        }
        .chartYScale(domain: 0 ... max(treadmill.speedMax, 1))
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) {
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .frame(height: 56)
    }

    private var today: some View {
        let total = Totals(treadmill.sessions.today, profile: profile)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Label("Today", systemImage: "calendar")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Format.steps(total.steps)) steps")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            Text(total.summary)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button { open(.settings) } label: {
                Label("Settings", systemImage: "gearshape")
            }
            Spacer()
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([treadmill.sessions.url])
            } label: { Image(systemName: "folder") }
                .help("Show session history in Finder")
            Button {
                treadmill.sessions.save()
                NSApp.terminate(nil)
            } label: { Image(systemName: "power") }
                .help("Quit")
        }
        .buttonStyle(.borderless)
        .font(.callout)
    }
}

private struct Stat: View {
    let title: String
    let icon: String
    let value: String?
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value ?? "—")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PageHeader: View {
    let title: String
    let back: () -> Void

    var body: some View {
        HStack {
            Button(action: back) {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)
            Spacer()
            Text(title).font(.headline)
            Spacer()
            Label("Back", systemImage: "chevron.left").hidden()
        }
    }
}

private struct Totals {
    var steps = 0, seconds = 0, meters = 0
    var kcal = 0.0

    init(_ sessions: [Session], profile: Profile) {
        for s in sessions {
            steps += profile.steps(for: s)
            seconds += s.duration
            meters += s.distance
            kcal += s.activeKcal ?? s.kcal
        }
    }

    var summary: String {
        "\(Format.duration(seconds)) · \(String(format: "%.1f km · %.0f kcal", Double(meters) / 1000, kcal))"
    }
}

private struct SettingsPage: View {
    let treadmill: Treadmill
    let close: () -> Void
    @State private var actualSteps: Int?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var profile: Profile { treadmill.profile }
    private var typicalSpeed: Double { treadmill.sessions.typicalSpeed ?? 3 }
    private var stepLength: Double? { profile.stepLength(speed: typicalSpeed) }

    var body: some View {
        @Bindable var profile = profile
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(title: "Settings", back: close)

            section("Profile") {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                    field("Weight", value: $profile.weight, unit: "kg")
                    field("Height", value: $profile.height, unit: "cm")
                    GridRow {
                        Text("Step").foregroundStyle(.secondary)
                        Text(stepLength.map { String(format: "%.0f", $0 * 100) } ?? "—")
                            .monospacedDigit()
                            .frame(width: 64, alignment: .trailing)
                            .padding(.trailing, 6)
                        Text("cm").foregroundStyle(.secondary)
                    }
                    GridRow {
                        Text("Age").foregroundStyle(.secondary)
                        TextField("", value: $profile.age, format: .number)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 64)
                        Text("years").foregroundStyle(.secondary)
                    }
                }
                Picker("Sex", selection: $profile.sex) {
                    Text("Male").tag(Sex.male)
                    Text("Female").tag(Sex.female)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if stepLength != nil {
                    note(String(format: "Average step length, calculated from your height at your usual %.1f km/h%@.",
                                typicalSpeed, treadmill.sessions.typicalSpeed == nil ? " (default until you have workouts)" : ""))
                }
            }

            section("Steps") {
                Picker("Steps", selection: $profile.stepSource) {
                    Text("Treadmill").tag(StepSource.treadmill)
                    Text("From height").tag(StepSource.model)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(profile.height <= 0)

                if profile.height <= 0 {
                    note("Enter your height to estimate steps from it.")
                } else if profile.usesStepModel {
                    note("Steps = distance ÷ step length. Slower walking means shorter steps, so it adapts to your speed.")
                    calibration
                } else {
                    note("Using the treadmill's own step counter.")
                }
            }

            section("Calories") {
                if let bmr = profile.bmrPerDay {
                    note(String(format: "Resting metabolic rate ≈ %.0f kcal/day (%.0f kcal/h).", bmr, bmr / 24))
                } else {
                    note("Weight, height and age are needed for resting calories.")
                }
                note("Active: ACSM walking equation, ≈ 0.5 kcal per kg per km. Resting: Mifflin-St Jeor.")
            }

            Toggle("Launch at login", isOn: $launchAtLogin)
                .toggleStyle(.switch)
                .controlSize(.small)
                .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
        }
    }

    @ViewBuilder private var calibration: some View {
        if let last = treadmill.sessions.lastFinished {
            let raw = Double(profile.steps(for: last)) / profile.stepFactor
            VStack(alignment: .leading, spacing: 6) {
                note("Calibrate: enter the real step count of your last session (\(Format.steps(profile.steps(for: last))) estimated).")
                HStack(spacing: 6) {
                    TextField("Actual steps", value: $actualSteps, format: .number)
                        .frame(width: 100)
                    Button("Calibrate") {
                        if let actual = actualSteps, actual > 0, raw > 0 {
                            profile.stepFactor = Double(actual) / raw
                            actualSteps = nil
                        }
                    }
                    .disabled((actualSteps ?? 0) <= 0)
                    Spacer()
                    if profile.stepFactor != 1 {
                        Text(String(format: "×%.2f", profile.stepFactor))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Button {
                            profile.stepFactor = 1
                        } label: { Image(systemName: "arrow.uturn.backward") }
                            .buttonStyle(.borderless)
                            .help("Reset calibration")
                    }
                }
                .controlSize(.small)
            }
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content()
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func field(_ title: String, value: Binding<Double>, unit: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            TextField("", value: value, format: .number.precision(.fractionLength(0 ... 1)))
                .multilineTextAlignment(.trailing)
                .frame(width: 64)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            treadmill.message = "Launch at login: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
