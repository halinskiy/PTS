import Cocoa

// MARK: - Particle System

final class ParticleSystem {
    var particles: [Particle] = []
    private weak var containerView: NSView?

    struct Particle {
        var view: ParticleView
        var x: CGFloat
        var y: CGFloat
        var velocityX: CGFloat
        var velocityY: CGFloat
        var life: CGFloat       // remaining seconds
        var maxLife: CGFloat
        var rotation: CGFloat
        var rotationSpeed: CGFloat
        var scale: CGFloat
        var type: ParticleType
    }

    enum ParticleType {
        case dust       // Landing dust puff
        case sleepZ     // Z's floating up during sleep
        case heart      // Hearts when petted
        case spark      // Sparks when running fast
        case star       // Stars when excited
        case sweat      // Sweat drop when CPU high
    }

    init(containerView: NSView) {
        self.containerView = containerView
    }

    // MARK: - Emitters

    func emitDust(at point: CGPoint, count: Int) {
        for _ in 0..<count {
            let angle = CGFloat.random(in: 0.3...2.8) // Upward-ish fan
            let speed = CGFloat.random(in: 40...120)
            let particle = createParticle(
                type: .dust,
                at: point,
                velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                life: CGFloat.random(in: 0.3...0.6),
                size: CGFloat.random(in: 2...4) * SCALE * 0.5
            )
            particles.append(particle)
        }
    }

    func emitSleepZ(at point: CGPoint) {
        let particle = createParticle(
            type: .sleepZ,
            at: CGPoint(x: point.x + CGFloat.random(in: -5...5), y: point.y + 20),
            velocity: CGVector(dx: CGFloat.random(in: -15...15), dy: CGFloat.random(in: 30...50)),
            life: 1.5,
            size: SCALE * 2
        )
        particles.append(particle)
    }

    func emitHeart(at point: CGPoint) {
        let particle = createParticle(
            type: .heart,
            at: CGPoint(x: point.x + CGFloat.random(in: -10...10), y: point.y + 20),
            velocity: CGVector(dx: CGFloat.random(in: -30...30), dy: CGFloat.random(in: 60...100)),
            life: 1.2,
            size: SCALE * 2.5
        )
        particles.append(particle)
    }

    func emitSparks(at point: CGPoint, direction: CGFloat) {
        for _ in 0..<3 {
            let particle = createParticle(
                type: .spark,
                at: point,
                velocity: CGVector(
                    dx: -direction * CGFloat.random(in: 80...160),
                    dy: CGFloat.random(in: 20...80)
                ),
                life: CGFloat.random(in: 0.2...0.4),
                size: SCALE * 0.8
            )
            particles.append(particle)
        }
    }

    func emitStar(at point: CGPoint) {
        let particle = createParticle(
            type: .star,
            at: CGPoint(x: point.x + CGFloat.random(in: -15...15), y: point.y + CGFloat.random(in: 10...30)),
            velocity: CGVector(dx: CGFloat.random(in: -20...20), dy: CGFloat.random(in: 30...60)),
            life: 0.8,
            size: SCALE * 1.5
        )
        particles.append(particle)
    }

    func emitSweat(at point: CGPoint) {
        let particle = createParticle(
            type: .sweat,
            at: CGPoint(x: point.x + 15, y: point.y + 25),
            velocity: CGVector(dx: 10, dy: -30),
            life: 0.8,
            size: SCALE * 1.5
        )
        particles.append(particle)
    }

    // MARK: - Update

    func update(dt: CGFloat) {
        var toRemove: [Int] = []

        for i in 0..<particles.count {
            particles[i].life -= dt
            if particles[i].life <= 0 {
                toRemove.append(i)
                continue
            }

            // Physics
            particles[i].x += particles[i].velocityX * dt
            particles[i].y += particles[i].velocityY * dt
            particles[i].rotation += particles[i].rotationSpeed * dt

            // Type-specific behavior
            switch particles[i].type {
            case .dust:
                particles[i].velocityY += 50 * dt // slight gravity resistance
                particles[i].velocityX *= (1 - 2 * dt)
                particles[i].velocityY *= (1 - 1.5 * dt)

            case .sleepZ:
                // Float upward, slight wave
                particles[i].velocityX = sin(particles[i].life * 4) * 20
                particles[i].scale = 0.5 + (1 - particles[i].life / particles[i].maxLife) * 0.8

            case .heart:
                // Float up with slight wave
                particles[i].velocityX = sin(particles[i].life * 3) * 15
                let lifeRatio = particles[i].life / particles[i].maxLife
                particles[i].scale = lifeRatio < 0.3 ? lifeRatio / 0.3 : 1.0

            case .spark:
                particles[i].velocityY -= 100 * dt // gravity
                particles[i].scale = particles[i].life / particles[i].maxLife

            case .star:
                particles[i].velocityY *= (1 - dt)
                let lifeRatio = particles[i].life / particles[i].maxLife
                particles[i].scale = sin(lifeRatio * .pi) // fade in and out

            case .sweat:
                particles[i].velocityY -= 200 * dt // gravity pulls down
                let lifeRatio = particles[i].life / particles[i].maxLife
                particles[i].scale = lifeRatio
            }

            // Update view
            let alpha = min(1, particles[i].life / (particles[i].maxLife * 0.3))
            let size = particles[i].scale * particles[i].view.baseSize
            particles[i].view.frame = CGRect(
                x: particles[i].x - size / 2,
                y: particles[i].y - size / 2,
                width: size,
                height: size
            )
            particles[i].view.alphaValue = alpha
            particles[i].view.particleRotation = particles[i].rotation
            particles[i].view.needsDisplay = true
        }

        // Remove dead particles
        for i in toRemove.reversed() {
            particles[i].view.removeFromSuperview()
            particles.remove(at: i)
        }
    }

    // MARK: - Factory

    private func createParticle(
        type: ParticleType,
        at point: CGPoint,
        velocity: CGVector,
        life: CGFloat,
        size: CGFloat
    ) -> Particle {
        let view = ParticleView(frame: CGRect(x: point.x, y: point.y, width: size, height: size))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.particleType = type
        view.baseSize = size
        containerView?.addSubview(view)

        return Particle(
            view: view,
            x: point.x,
            y: point.y,
            velocityX: velocity.dx,
            velocityY: velocity.dy,
            life: life,
            maxLife: life,
            rotation: 0,
            rotationSpeed: CGFloat.random(in: -3...3),
            scale: 1,
            type: type
        )
    }

    func removeAll() {
        for p in particles {
            p.view.removeFromSuperview()
        }
        particles.removeAll()
    }
}
