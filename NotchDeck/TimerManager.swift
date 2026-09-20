import AppKit
import Combine

final class TimerManager: ObservableObject {
    enum Phase: String { case idle, running, paused, done }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var remaining: TimeInterval = 25 * 60
    @Published private(set) var total: TimeInterval = 25 * 60
    @Published var pomodoro = false
    @Published private(set) var pomodoroRound = 1
    @Published private(set) var onBreak = false
    @Published private(set) var finishedAt: Date?

    private var endDate: Date?
    private var tick: Timer?

    var progress: Double { total > 0 ? 1 - remaining / total : 0 }
    var isActive: Bool { phase == .running || phase == .paused }

    func set(minutes: Double) {
        guard phase != .running else { return }
        total = minutes * 60
        remaining = total
        phase = .idle
        onBreak = false
    }

    func start() {
        if phase == .done { remaining = total; onBreak = false }
        endDate = Date().addingTimeInterval(remaining)
        phase = .running
        tick?.invalidate()
        tick = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.update() }
        RunLoop.main.add(tick!, forMode: .common)
    }

    func pause() {
        guard phase == .running else { return }
        update()
        phase = .paused
        tick?.invalidate()
    }

    func toggle() { phase == .running ? pause() : start() }

    func reset() {
        tick?.invalidate()
        phase = .idle
        onBreak = false
        pomodoroRound = 1
        remaining = total
    }

    private func update() {
        guard let end = endDate else { return }
        remaining = max(0, end.timeIntervalSinceNow)
        if remaining <= 0 { finish() }
    }

    private func finish() {
        tick?.invalidate()
        phase = .done
        finishedAt = Date()
        SoundKit.play(.timerDone, force: true)
        if pomodoro {
            if onBreak {
                onBreak = false
                pomodoroRound += 1
                total = 25 * 60
            } else {
                onBreak = true
                total = (pomodoroRound % 4 == 0 ? 15 : 5) * 60
            }
            remaining = total
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, self.phase == .done else { return }
                self.start()
            }
        }
    }

    var display: String {
        let t = Int(remaining.rounded())
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
