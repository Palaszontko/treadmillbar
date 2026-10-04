import Foundation
import Observation

enum Sex: String, CaseIterable {
    case male, female
}

enum StepSource: String, CaseIterable {
    case treadmill, model
}

@Observable
final class Profile {
    var weight: Double { didSet { defaults.set(weight, forKey: "weight") } }
    var height: Double {
        didSet {
            defaults.set(height, forKey: "height")
            if oldValue <= 0 && height > 0 { stepSource = .model }
        }
    }
    var age: Int { didSet { defaults.set(age, forKey: "age") } }
    var sex: Sex { didSet { defaults.set(sex.rawValue, forKey: "sex") } }
    var stepSource: StepSource { didSet { defaults.set(stepSource.rawValue, forKey: "stepSource") } }
    var stepFactor: Double { didSet { defaults.set(stepFactor, forKey: "stepFactor") } }
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        weight = defaults.double(forKey: "weight")
        height = defaults.double(forKey: "height")
        age = defaults.integer(forKey: "age")
        sex = Sex(rawValue: defaults.string(forKey: "sex") ?? "") ?? .male
        stepSource = StepSource(rawValue: defaults.string(forKey: "stepSource") ?? "") ?? (defaults.double(forKey: "height") > 0 ? .model : .treadmill)
        stepFactor = defaults.object(forKey: "stepFactor") as? Double ?? 1
    }

    var usesStepModel: Bool { stepSource == .model && height > 0 }

    func steps(for session: Session) -> Int {
        guard usesStepModel else { return session.steps }
        let raw = session.modelSteps
            ?? Gait.steps(distance: session.distance, speed: session.averageSpeed, height: height)
        return Int((raw * stepFactor).rounded())
    }

    func stepLength(speed: Double) -> Double? {
        guard height > 0, stepFactor > 0 else { return nil }
        return Gait.stepLength(speed: speed, height: height) / stepFactor
    }

    var hasWeight: Bool { weight > 0 }

    /// Mifflin-St Jeor resting metabolic rate [kcal/day].
    var bmrPerDay: Double? {
        guard weight > 0, height > 0, age > 0 else { return nil }
        return 10 * weight + 6.25 * height - 5 * Double(age) + (sex == .male ? 5 : -161)
    }
}
