import Foundation

public final class InputTransaction {
    public enum Step { case prepare, selected, inserted, confirmed, restore, restored }
    public enum Check { case ready, waiting, rejected }
    public enum Outcome: Equatable { case confirmed, restored, uncertain }
    // Admission deadline. Exact readback/recovery may finish later after external IPC stalls.
    public static let admissionDuration = 0.2
    public static let handoff = 0.008
    public static let maximumChecks = 8
    // Two bounded AX readbacks, one setter, both handoffs and scheduling margin.
    public static let postingReserve = 0.12

    private enum Phase { case preparing, selected, posted, verifying, recovering, finished }
    private var phase = Phase.preparing
    private let perform: (Step) -> Check
    private let post: () -> Void
    private let later: (@escaping () -> Void) -> Void
    private let completion: (Outcome) -> Void

    public init(perform: @escaping (Step) -> Check, post: @escaping () -> Void,
                later: @escaping (@escaping () -> Void) -> Void,
                completion: @escaping (Outcome) -> Void) {
        self.perform = perform; self.post = post; self.later = later; self.completion = completion
    }

    public func start() {
        guard phase == .preparing else { return }
        guard perform(.prepare) == .ready else { abort(); return }
        phase = .selected
        later { [self] in
            verify(.selected, phase: .selected) { [self] in
                phase = .posted
                post()
                later { [self] in
                    verify(.inserted, phase: .posted) { [self] in
                        phase = .verifying
                        later { [self] in
                            verify(.confirmed, phase: .verifying) { [self] in finish(.confirmed) }
                        }
                    }
                }
            }
        }
    }

    public func abort() {
        guard phase != .finished && phase != .recovering else { return }
        guard phase == .preparing || phase == .selected else { finish(.uncertain); return }
        phase = .recovering
        guard perform(.restore) == .ready else { finish(.uncertain); return }
        // A successful AX setter is an accepted request, not an immediate editor update.
        later { [self] in
            verify(.restored, phase: .recovering) { [self] in finish(.restored) }
        }
    }

    private func verify(_ step: Step, phase expected: Phase, attempt: Int = 1, ready: @escaping () -> Void) {
        guard phase == expected else { return }
        let result = perform(step)
        guard phase == expected else { return }
        switch result {
        case .ready: ready()
        case .waiting where attempt < Self.maximumChecks:
            later { [self] in verify(step, phase: expected, attempt: attempt + 1, ready: ready) }
        default:
            if phase == .recovering { finish(.uncertain) } else { abort() }
        }
    }

    public func expire() {
        if phase == .recovering { cancel() } else { abort() }
    }

    // A disabled or overflowing tap has already lost its ability to preserve queued input.
    public func cancel() { finish(.uncertain) }

    private func finish(_ outcome: Outcome) {
        guard phase != .finished else { return }
        phase = .finished
        completion(outcome)
    }
}
