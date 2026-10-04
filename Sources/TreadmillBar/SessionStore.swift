import Foundation
import Observation

struct Session: Codable, Identifiable {
    var id = UUID()
    var start: Date
    var end: Date
    var duration: Int
    var steps: Int
    var distance: Int
    var kcal: Double
    var activeKcal: Double? = nil
    var modelSteps: Double? = nil

    var averageSpeed: Double { Double(distance) / Double(max(duration, 1)) * 3.6 }
}

@Observable
final class SessionStore {
    private(set) var sessions: [Session] = []
    @ObservationIgnored private var currentID: UUID?
    @ObservationIgnored private var lastSaved = Date.distantPast
    @ObservationIgnored private var weight = 0.0
    @ObservationIgnored private var height = 0.0
    @ObservationIgnored let url: URL

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TreadmillBar/sessions.json")
    }

    init(url: URL = SessionStore.defaultURL) {
        self.url = url
        if let data = try? Data(contentsOf: url) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            sessions = (try? decoder.decode([Session].self, from: data)) ?? []
        }
    }

    var today: [Session] { sessions.filter { Calendar.current.isDateInToday($0.start) } }

    func update(with s: Sample, at now: Date = Date(), weight: Double = 0, height: Double = 0) {
        self.weight = weight
        self.height = height
        guard s.time > 0 else {
            finishCurrent()
            return
        }
        if let i = currentIndex {
            if s.time + 5 < sessions[i].duration {
                finishCurrent()
                startOrResume(s, now)
            } else if s.time != sessions[i].duration || s.steps != sessions[i].steps {
                apply(s, to: i, now)
            }
        } else {
            startOrResume(s, now)
        }
        if now.timeIntervalSince(lastSaved) > 10 { save() }
    }

    func finishCurrent() {
        guard let i = currentIndex else { return }
        if sessions[i].duration < 30 && sessions[i].steps < 20 { sessions.remove(at: i) }
        currentID = nil
        save()
    }

    var current: Session? { currentIndex.map { sessions[$0] } }

    var lastFinished: Session? { sessions.last { $0.steps > 100 } }

    var typicalSpeed: Double? {
        let recent = sessions.suffix(20).filter { $0.duration >= 60 && $0.distance > 0 }
        let seconds = recent.reduce(0) { $0 + $1.duration }
        guard seconds > 0 else { return nil }
        return Double(recent.reduce(0) { $0 + $1.distance }) / Double(seconds) * 3.6
    }

    private var currentIndex: Int? { currentID.flatMap { id in sessions.firstIndex { $0.id == id } } }

    private func startOrResume(_ s: Sample, _ now: Date) {
        if let i = sessions.indices.last {
            let last = sessions[i]
            let wallElapsed = now.timeIntervalSince(last.end)
            if wallElapsed < 3600, last.duration <= s.time + 5, last.steps <= s.steps,
               Double(s.time - last.duration) <= wallElapsed + 60 {
                currentID = last.id
                apply(s, to: i, now)
                return
            }
        }
        let session = Session(start: now.addingTimeInterval(-Double(s.time)), end: now, duration: s.time,
                              steps: s.steps, distance: 0, kcal: s.kcal)
        sessions.append(session)
        currentID = session.id
        apply(s, to: sessions.count - 1, now)
    }

    private func apply(_ s: Sample, to i: Int, _ now: Date) {
        if height > 0, sessions[i].modelSteps == nil, sessions[i].distance > 0 {
            sessions[i].modelSteps = Gait.steps(distance: sessions[i].distance, speed: sessions[i].averageSpeed,
                                                height: height)
        }
        let delta = s.distance - sessions[i].distance
        if height > 0, delta > 0 {
            sessions[i].modelSteps = (sessions[i].modelSteps ?? 0)
                + Gait.steps(distance: delta, speed: s.speed, height: height)
        }
        sessions[i].end = now
        sessions[i].duration = s.time
        sessions[i].steps = s.steps
        sessions[i].distance = s.distance
        sessions[i].kcal = s.kcal
        sessions[i].activeKcal = weight > 0 ? Energy.active(distance: s.distance, weight: weight) : nil
    }

    func save() {
        lastSaved = Date()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(sessions) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
