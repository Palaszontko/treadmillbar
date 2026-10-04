import Foundation

/// Energy cost of walking from the ACSM metabolic equation:
///   VO2 [ml/kg/min] = 3.5 (rest) + 0.1 · v + 1.8 · v · grade,   v in m/min
/// and ~5 kcal per litre of O2. "Active" energy excludes the resting 3.5 term,
/// which matches Apple Health's active energy. Valid for walking ~3–6 km/h; at
/// very slow speeds it is a rougher estimate.
enum Energy {
    static let kcalPerLitreO2 = 5.0

    static func vo2(speed kmh: Double, grade: Double = 0) -> Double {
        let v = kmh * 1000 / 60
        return 3.5 + 0.1 * v + 1.8 * v * grade
    }

    static func met(speed kmh: Double, grade: Double = 0) -> Double {
        vo2(speed: kmh, grade: grade) / 3.5
    }

    /// Active energy expenditure rate [kcal/h].
    static func activePerHour(speed kmh: Double, weight: Double, grade: Double = 0) -> Double {
        (vo2(speed: kmh, grade: grade) - 3.5) * weight * 60 / 1000 * kcalPerLitreO2
    }

    /// Active energy for a distance walked on a flat belt [kcal]. On the flat the
    /// equation is linear in speed, so it reduces to 0.1 ml O2 per kg per metre:
    /// 0.5 kcal per kg per km, independent of how fast.
    static func active(distance metres: Int, weight: Double) -> Double {
        0.1 * Double(metres) * weight / 1000 * kcalPerLitreO2
    }

    /// Resting energy burnt over a duration [kcal].
    static func resting(seconds: Int, bmrPerDay: Double) -> Double {
        bmrPerDay * Double(seconds) / 86400
    }
}

/// Step length model. Step length is ~0.415 × height at a normal pace (~5 km/h)
/// and shortens at slower speeds; the square-root scaling is an approximation,
/// which is why the result can be calibrated per person.
enum Gait {
    static let referenceSpeed = 5.0

    /// Step length [m] at a given speed [km/h] for a height [cm].
    static func stepLength(speed: Double, height: Double) -> Double {
        let v = min(max(speed, 0.5), 7)
        return 0.415 * height / 100 * (v / referenceSpeed).squareRoot()
    }

    static func steps(distance metres: Int, speed: Double, height: Double) -> Double {
        Double(metres) / stepLength(speed: speed, height: height)
    }

    static func cadence(speed: Double, height: Double) -> Double {
        speed * 1000 / 60 / stepLength(speed: speed, height: height)
    }
}
