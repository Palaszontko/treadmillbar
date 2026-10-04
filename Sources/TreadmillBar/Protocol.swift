import CoreBluetooth
import Foundation

enum GATT {
    static let fitshowService = CBUUID(string: "FFF0")
    static let fitshowNotify = CBUUID(string: "FFF1")
    static let fitshowWrite = CBUUID(string: "FFF2")
    static let ftmsService = CBUUID(string: "1826")
    static let controlPoint = CBUUID(string: "2AD9")
    static let speedRange = CBUUID(string: "2AD4")
}

struct Sample: Equatable {
    var status: UInt8
    var speed: Double = 0
    var incline: Int = 0
    var time: Int = 0
    var distance: Int = 0
    var kcal: Double = 0
    var steps: Int = 0
}

enum FitShow {
    static let statusQuery = Data([0x02, 0x51, 0x51, 0x03])

    static func parse(_ data: Data) -> Sample? {
        let b = [UInt8](data)
        guard b.count >= 5, b[0] == 0x02, b[b.count - 1] == 0x03, b[1] == 0x51 else { return nil }
        let xor = b[1 ..< b.count - 2].reduce(0, ^)
        guard xor == b[b.count - 2] else { return nil }
        guard b.count >= 15 else { return Sample(status: b[2]) }
        func u16(_ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 }
        return Sample(
            status: b[2],
            speed: Double(b[3]) / 10,
            incline: Int(b[4]),
            time: u16(5),
            distance: u16(7),
            kcal: Double(u16(9)) / 10,
            steps: u16(11)
        )
    }

    static let running: UInt8 = 3

    static func statusName(_ s: UInt8) -> String {
        switch s {
        case 0: "Ready"
        case 1: "Finished"
        case 2: "Starting…"
        case 3: "Running"
        case 4: "Stopping"
        case 5: "Error"
        case 6: "Safety key"
        case 10: "Paused"
        default: "Status \(s)"
        }
    }
}

enum FTMS {
    static let requestControl = Data([0x00])
    static let start = Data([0x07])
    static let stop = Data([0x08, 0x01])
    static let pause = Data([0x08, 0x02])

    static func setSpeed(_ kmh: Double) -> Data {
        let v = UInt16((kmh * 100).rounded())
        return Data([0x02, UInt8(v & 0xFF), UInt8(v >> 8)])
    }

    static func opName(_ op: UInt8) -> String {
        switch op {
        case 0x00: "Request control"
        case 0x02: "Set speed"
        case 0x07: "Start"
        case 0x08: "Stop/pause"
        default: String(format: "op 0x%02x", op)
        }
    }

    static func resultName(_ r: UInt8) -> String {
        switch r {
        case 1: "OK"
        case 2: "not supported"
        case 3: "invalid parameter"
        case 4: "failed"
        case 5: "control not permitted"
        default: "result \(r)"
        }
    }
}

enum Format {
    private static let stepFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f
    }()

    static func steps(_ n: Int) -> String {
        stepFormatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    static func time(_ s: Int) -> String {
        let h = s / 3600, m = s % 3600 / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }

    static func duration(_ s: Int) -> String {
        let h = s / 3600, m = s % 3600 / 60
        return h > 0 ? "\(h) h \(m) min" : "\(m) min"
    }

    static func pace(_ kmh: Double) -> String {
        guard kmh > 0 else { return "–:––" }
        let sec = Int((3600 / kmh).rounded())
        return String(format: "%d:%02d", sec / 60, sec % 60)
    }
}
