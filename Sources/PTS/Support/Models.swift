import Cocoa

enum CrabLevel {
    case dock
    case ground
    case window
}

enum JumpPhase {
    case none
    case squish
    case climbing
    case airborne
    case land
}

enum ApplePhase {
    case falling
    case bounce
    case resting
}

struct AppleState {
    var view: AppleView
    var phase: ApplePhase = .falling
    var x: CGFloat = 0
    var y: CGFloat = 0
    var previousX: CGFloat = 0
    var previousY: CGFloat = 0
    var crabHitCooldown: CGFloat = 0
    var velocityX: CGFloat = 0
    var velocityY: CGFloat = 0
    var rotation: CGFloat = 0
    var rotationSpeed: CGFloat = 0
    var floorY: CGFloat = 0
    var bounceCount = 0
    var settleRotation: CGFloat = 0
    var settleWobbleTime: CGFloat = 0
}
