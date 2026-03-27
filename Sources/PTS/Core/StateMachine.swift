import Foundation

// MARK: - Generic State Machine

protocol MascotStateProtocol: AnyObject {
    func enter(mascot: MascotEntity)
    func update(dt: CGFloat, mascot: MascotEntity)
    func exit(mascot: MascotEntity)
    var canBeInterrupted: Bool { get }
}

extension MascotStateProtocol {
    var canBeInterrupted: Bool { true }
}

final class MascotStateMachine {
    private(set) var currentState: MascotStateProtocol?
    private(set) var previousStateType: String = ""
    private var states: [String: MascotStateProtocol] = [:]

    func register<S: MascotStateProtocol>(_ state: S, for key: String) {
        states[key] = state
    }

    func transition(to key: String, mascot: MascotEntity) {
        guard let nextState = states[key] else { return }
        if let current = currentState, !current.canBeInterrupted { return }
        currentState?.exit(mascot: mascot)
        previousStateType = stateKey ?? ""
        currentState = nextState
        nextState.enter(mascot: mascot)
    }

    func forceTransition(to key: String, mascot: MascotEntity) {
        guard let nextState = states[key] else { return }
        currentState?.exit(mascot: mascot)
        previousStateType = stateKey ?? ""
        currentState = nextState
        nextState.enter(mascot: mascot)
    }

    func update(dt: CGFloat, mascot: MascotEntity) {
        currentState?.update(dt: dt, mascot: mascot)
    }

    var stateKey: String? {
        guard let current = currentState else { return nil }
        return states.first(where: { $0.value === current })?.key
    }

    func isIn(_ key: String) -> Bool {
        stateKey == key
    }
}
