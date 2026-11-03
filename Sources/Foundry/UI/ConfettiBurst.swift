import SwiftUI

struct ConfettiBurst: View {
    let trigger: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.distantPast
    @State private var particles: [Particle] = []
    @State private var seededTrigger = 0
    @State private var isActive = false

    static let duration: TimeInterval = 2.4
    private static let maxDelay: TimeInterval = 0.5
    static let palette: [Color] = FoundryTheme.confettiColors + [.white]

    var body: some View {
        // Paused while idle — an untriggered TimelineView still ticks a
        // 60 fps Canvas for the entire life of the panel.
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: isActive == false)) { context in
            let elapsed = context.date.timeIntervalSince(start)
            Canvas { canvas, size in
                for particle in particles {
                    let age = elapsed - particle.delay
                    guard age > 0, age < Self.duration else { continue }
                    let fall = pow(age / Self.duration, 1.15)
                    let y = -14 + fall * (size.height + 60)
                    let x = particle.originX * size.width
                        + sin(age * particle.swaySpeed + particle.phase) * particle.drift
                        + particle.lateralDrift * age
                    var layer = canvas
                    layer.opacity = min(1, (Self.duration - age) / 0.55)
                    layer.translateBy(x: x, y: y)
                    layer.rotate(by: .radians(age * particle.spin))
                    layer.fill(particle.path(size: particle.size), with: .color(Self.palette[particle.colorIndex]))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, newTrigger in
            guard newTrigger > 0, newTrigger != seededTrigger else { return }
            seededTrigger = newTrigger
            start = Date()
            particles = Self.seed(count: reduceMotion ? 0 : 90)
            isActive = particles.isEmpty == false
        }
        .task(id: seededTrigger) {
            guard seededTrigger > 0, isActive else { return }
            try? await Task.sleep(for: .seconds(Self.duration + Self.maxDelay))
            guard Task.isCancelled == false else { return }
            isActive = false
            particles = []
        }
    }

    static func seed(count: Int) -> [Particle] {
        var generator = SplitMix64(seed: UInt64.random(in: .min ... .max))
        return (0 ..< count).map { _ in
            Particle(
                originX: generator.nextUnit() * 0.9 + 0.05,
                delay: generator.nextUnit() * 0.5,
                drift: 14 + generator.nextUnit() * 30,
                lateralDrift: (generator.nextUnit() - 0.5) * 26,
                swaySpeed: 2.2 + generator.nextUnit() * 4.5,
                spin: (generator.nextUnit() - 0.5) * 12,
                phase: generator.nextUnit() * .pi * 2,
                size: 5 + generator.nextUnit() * 7,
                shapeIndex: Int(generator.next() % 4),
                colorIndex: Int(generator.next() % UInt64(palette.count))
            )
        }
    }

    struct Particle {
        let originX: Double
        let delay: TimeInterval
        let drift: CGFloat
        let lateralDrift: CGFloat
        let swaySpeed: Double
        let spin: Double
        let phase: Double
        let size: Double
        let shapeIndex: Int
        let colorIndex: Int

        func path(size: Double) -> Path {
            let r = size / 2
            switch shapeIndex {
            case 0:
                return Path(ellipseIn: CGRect(x: -r, y: -r, width: size, height: size))
            case 1:
                return Path(roundedRect: CGRect(x: -r, y: -r * 0.7, width: size, height: size * 0.7), cornerRadius: FoundryTheme.Radius.tile)
            case 2:
                var path = Path()
                path.move(to: CGPoint(x: 0, y: -r))
                path.addLine(to: CGPoint(x: r, y: r))
                path.addLine(to: CGPoint(x: -r, y: r))
                path.closeSubpath()
                return path
            default:
                return Path(ellipseIn: CGRect(x: -r * 0.6, y: -r, width: size * 0.6, height: size))
            }
        }
    }

    struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        mutating func nextUnit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    }
}
