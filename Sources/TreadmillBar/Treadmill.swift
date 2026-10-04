import CoreBluetooth
import Foundation
import Observation

struct SpeedPoint: Identifiable {
    let id = UUID()
    let date: Date
    let speed: Double
}

@Observable
final class Treadmill: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    enum LinkState { case bluetoothOff, scanning, connecting, connected }

    var linkState: LinkState = .scanning
    var deviceName = "Treadmill"
    var sample: Sample?
    var hasControl = false
    var message = "" {
        didSet { if Self.debug, message != oldValue { print("[msg] \(message)") } }
    }
    var speedMin = 1.0
    var speedMax = 8.0
    var target: Double?
    var cadence: Double?
    var speedHistory: [SpeedPoint] = []
    let sessions: SessionStore
    let profile: Profile

    static let debug = ProcessInfo.processInfo.environment["TREADMILLBAR_DEBUG"] == "1"

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var writeChar: CBCharacteristic?
    @ObservationIgnored private var controlChar: CBCharacteristic?
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var speedWork: DispatchWorkItem?
    @ObservationIgnored private var stepWindow: [(date: Date, steps: Int)] = []
    @ObservationIgnored private var targetSetAt = Date.distantPast
    @ObservationIgnored private var lastHistoryAt = Date.distantPast

    init(sessions: SessionStore = SessionStore(), profile: Profile = Profile(), startBluetooth: Bool = true) {
        self.sessions = sessions
        self.profile = profile
        super.init()
        if startBluetooth {
            central = CBCentralManager(delegate: self, queue: .main)
        }
    }

    var isConnected: Bool { linkState == .connected }

    var displaySteps: Int? {
        guard let sample else { return nil }
        if profile.usesStepModel, let current = sessions.current { return profile.steps(for: current) }
        return sample.steps
    }

    var displayCadence: Double? {
        guard profile.usesStepModel else { return cadence }
        guard let sample, isRunning, sample.speed > 0 else { return nil }
        return Gait.cadence(speed: sample.speed, height: profile.height) * profile.stepFactor
    }

    var isRunning: Bool { sample?.status == FitShow.running }

    func start() { sendControl(FTMS.start) }
    func pause() { sendControl(FTMS.pause) }

    func stop() {
        target = nil
        sendControl(FTMS.stop)
    }

    func nudge(_ delta: Double) {
        setSpeed((target ?? sample?.speed ?? 0) + delta)
    }

    func setSpeed(_ kmh: Double) {
        guard isRunning else {
            message = "Start the belt first"
            return
        }
        let value = (min(max(kmh, speedMin), speedMax) * 10).rounded() / 10
        target = value
        targetSetAt = Date()
        speedWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.sendControl(FTMS.setSpeed(value)) }
        speedWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func sendControl(_ data: Data) {
        guard let peripheral, let controlChar else {
            message = "Not connected to the treadmill"
            return
        }
        if !hasControl && data != FTMS.requestControl {
            peripheral.writeValue(FTMS.requestControl, for: controlChar, type: .withResponse)
        }
        peripheral.writeValue(data, for: controlChar, type: .withResponse)
    }

    private func findDevice() {
        guard let central, central.state == .poweredOn else { return }
        if let p = central.retrieveConnectedPeripherals(withServices: [GATT.fitshowService]).first {
            connect(p)
            return
        }
        linkState = .scanning
        message = "Searching for treadmill…"
        central.scanForPeripherals(withServices: nil)
    }

    private func connect(_ p: CBPeripheral) {
        peripheral = p
        p.delegate = self
        deviceName = p.name ?? deviceName
        linkState = .connecting
        message = "Connecting to \(deviceName)…"
        central?.connect(p)
    }

    private func reset() {
        pollTimer?.invalidate()
        pollTimer = nil
        peripheral = nil
        writeChar = nil
        controlChar = nil
        hasControl = false
        sample = nil
        target = nil
        cadence = nil
        stepWindow.removeAll()
        sessions.save()
    }

    private func reconnectSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.findDevice() }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            findDevice()
        } else {
            reset()
            linkState = .bluetoothOff
            message = central.state == .unauthorized ? "Bluetooth access denied" : "Bluetooth is off"
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData ad: [String: Any], rssi: NSNumber) {
        let name = p.name ?? ad[CBAdvertisementDataLocalNameKey] as? String ?? ""
        let uuids = ad[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let looksLikeFitShow = uuids.contains(GATT.fitshowService) && uuids.contains(GATT.ftmsService)
        guard looksLikeFitShow || name.hasPrefix("HS") else { return }
        central.stopScan()
        connect(p)
    }

    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        p.discoverServices([GATT.fitshowService, GATT.ftmsService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        reset()
        message = "Connection failed"
        reconnectSoon()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        reset()
        linkState = .scanning
        message = "Disconnected"
        reconnectSoon()
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] { p.discoverCharacteristics(nil, for: s) }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] {
            switch c.uuid {
            case GATT.fitshowNotify: p.setNotifyValue(true, for: c)
            case GATT.fitshowWrite:
                writeChar = c
                startPolling()
            case GATT.controlPoint:
                controlChar = c
                p.setNotifyValue(true, for: c)
            case GATT.speedRange: p.readValue(for: c)
            default: break
            }
        }
    }

    private func startPolling() {
        linkState = .connected
        message = "Connected"
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let peripheral = self.peripheral, let writeChar = self.writeChar else { return }
            peripheral.writeValue(FitShow.statusQuery, for: writeChar, type: .withoutResponse)
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor c: CBCharacteristic, error: Error?) {
        if c.uuid == GATT.controlPoint && c.isNotifying {
            sendControl(FTMS.requestControl)
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        guard let data = c.value else { return }
        switch c.uuid {
        case GATT.fitshowNotify:
            if let s = FitShow.parse(data) { handle(s) }
        case GATT.controlPoint:
            handleControlResponse(data)
        case GATT.speedRange where data.count >= 4:
            let b = [UInt8](data)
            speedMin = Double(Int(b[0]) | Int(b[1]) << 8) / 100
            speedMax = Double(Int(b[2]) | Int(b[3]) << 8) / 100
        default:
            break
        }
    }

    func peripheral(_ p: CBPeripheral, didWriteValueFor c: CBCharacteristic, error: Error?) {
        if let error { message = "Write error: \(error.localizedDescription)" }
    }

    private func handle(_ s: Sample) {
        let now = Date()
        if Self.debug { print("[sample] \(s)") }
        sample = s
        if s.status == FitShow.running {
            stepWindow.append((now, s.steps))
            stepWindow.removeAll { now.timeIntervalSince($0.date) > 30 }
            if let first = stepWindow.first, let last = stepWindow.last,
               last.date.timeIntervalSince(first.date) >= 5, last.steps >= first.steps {
                cadence = Double(last.steps - first.steps) / last.date.timeIntervalSince(first.date) * 60
            }
            if now.timeIntervalSince(lastHistoryAt) >= 1 {
                lastHistoryAt = now
                speedHistory.append(SpeedPoint(date: now, speed: s.speed))
                speedHistory.removeAll { now.timeIntervalSince($0.date) > 600 }
            }
        } else {
            stepWindow.removeAll()
            cadence = nil
            target = nil
        }
        if let t = target, abs(s.speed - t) < 0.05 || now.timeIntervalSince(targetSetAt) > 15 {
            target = nil
        }
        sessions.update(with: s, at: now, weight: profile.weight, height: profile.height)
    }

    private func handleControlResponse(_ data: Data) {
        let b = [UInt8](data)
        guard b.count >= 3, b[0] == 0x80 else { return }
        if b[1] == 0x00 { hasControl = b[2] == 1 }
        if b[2] == 5 { hasControl = false }
        message = "\(FTMS.opName(b[1])): \(FTMS.resultName(b[2]))"
    }
}
