import CoreGraphics
import Foundation

public enum WindowPlacement: String, Codable, Hashable, Sendable, CaseIterable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case leftThird, centerThird, rightThird
    case leftTwoThirds, centerTwoThirds, rightTwoThirds
    case firstFourth, secondFourth, thirdFourth, lastFourth
    case firstThreeFourths, lastThreeFourths
    case maximize, almostMaximize, maximizeHeight, center, centerHalf
    case increaseSize, decreaseSize
    case nudgeLeft, nudgeRight, nudgeUp, nudgeDown
    case nextDisplay, previousDisplay
    case restore

    public static let homeDefaults: [WindowPlacement] = [.leftHalf, .rightHalf, .topHalf, .maximize, .center, .restore]

    public var isManagerHandled: Bool {
        switch self {
        case .nextDisplay, .previousDisplay, .restore: true
        default: false
        }
    }
}

public enum WindowLayoutGroup: String, CaseIterable, Hashable, Sendable {
    case common
    case halves
    case quarters
    case thirds
    case fourths
    case window
    case displays

    public var placements: [WindowPlacement] {
        switch self {
        case .common: [.leftHalf, .rightHalf, .maximize, .restore, .almostMaximize]
        case .halves: [.topHalf, .bottomHalf]
        case .quarters: [.topLeft, .topRight, .bottomLeft, .bottomRight]
        case .thirds: [.leftThird, .centerThird, .rightThird, .leftTwoThirds, .centerTwoThirds, .rightTwoThirds]
        case .fourths: [.firstFourth, .secondFourth, .thirdFourth, .lastFourth, .firstThreeFourths, .lastThreeFourths]
        case .window: [.center, .increaseSize, .decreaseSize, .nudgeLeft, .nudgeRight, .nudgeUp, .nudgeDown, .maximizeHeight, .centerHalf]
        case .displays: [.nextDisplay, .previousDisplay]
        }
    }
}

public enum WindowLayoutQuery {
    public static let overviewResultLimit = 40
    public static let overviewKeywords = ["tile", "window", "windows", "layout", "layouts", "snap"]

    public static func isOverview(_ query: String) -> Bool {
        overviewKeywords.contains(query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}

public struct WindowLayoutOptions: Sendable, Equatable {
    public var gap: CGFloat
    public var nudgeDistance: CGFloat
    public var resizeStep: CGFloat
    public var minimumSize: CGSize

    public init(gap: CGFloat, nudgeDistance: CGFloat, resizeStep: CGFloat, minimumSize: CGSize) {
        self.gap = gap
        self.nudgeDistance = nudgeDistance
        self.resizeStep = resizeStep
        self.minimumSize = minimumSize
    }

    public static let `default` = WindowLayoutOptions(gap: 6, nudgeDistance: 10, resizeStep: 10, minimumSize: CGSize(width: 200, height: 140))
}

public enum WindowLayoutEngine {
    public static func frame(for placement: WindowPlacement, currentFrame: CGRect, visibleFrame: CGRect, options: WindowLayoutOptions = .default) -> CGRect? {
        guard placement.isManagerHandled == false else { return nil }
        let usable = visibleFrame.insetBy(dx: options.gap, dy: options.gap)
        guard usable.width >= 1, usable.height >= 1 else { return nil }

        switch placement {
        case .leftHalf:
            return CGRect(x: usable.minX, y: usable.minY, width: usable.width / 2, height: usable.height)
        case .rightHalf:
            let width = usable.width / 2
            return CGRect(x: usable.maxX - width, y: usable.minY, width: width, height: usable.height)
        case .topHalf:
            let height = usable.height / 2
            return CGRect(x: usable.minX, y: usable.maxY - height, width: usable.width, height: height)
        case .bottomHalf:
            return CGRect(x: usable.minX, y: usable.minY, width: usable.width, height: usable.height / 2)
        case .topLeft:
            return CGRect(x: usable.minX, y: usable.midY, width: usable.width / 2, height: usable.height / 2)
        case .topRight:
            return CGRect(x: usable.midX, y: usable.midY, width: usable.width / 2, height: usable.height / 2)
        case .bottomLeft:
            return CGRect(x: usable.minX, y: usable.minY, width: usable.width / 2, height: usable.height / 2)
        case .bottomRight:
            return CGRect(x: usable.midX, y: usable.minY, width: usable.width / 2, height: usable.height / 2)
        case .leftThird:
            return CGRect(x: usable.minX, y: usable.minY, width: usable.width / 3, height: usable.height)
        case .centerThird:
            let width = usable.width / 3
            return CGRect(x: usable.minX + width, y: usable.minY, width: width, height: usable.height)
        case .rightThird:
            let width = usable.width / 3
            return CGRect(x: usable.maxX - width, y: usable.minY, width: width, height: usable.height)
        case .leftTwoThirds, .centerTwoThirds, .rightTwoThirds, .firstFourth, .secondFourth, .thirdFourth, .lastFourth, .firstThreeFourths, .lastThreeFourths, .centerHalf:
            guard let (start, fraction) = placement.columnSpan else { return nil }
            return CGRect(x: usable.minX + usable.width * start, y: usable.minY, width: usable.width * fraction, height: usable.height)
        case .maximize:
            return usable
        case .almostMaximize:
            return usable.insetBy(dx: usable.width * 0.05, dy: usable.height * 0.05)
        case .maximizeHeight:
            let width = min(currentFrame.width, usable.width)
            return CGRect(x: clamped(currentFrame.minX, in: usable.minX...(usable.maxX - width)), y: usable.minY, width: width, height: usable.height)
        case .center:
            var size = currentFrame.size
            size.width = min(size.width, usable.width)
            size.height = min(size.height, usable.height)
            return CGRect(origin: CGPoint(x: usable.midX - size.width / 2, y: usable.midY - size.height / 2), size: size)
        case .increaseSize, .decreaseSize:
            let step = placement == .increaseSize ? options.resizeStep : -options.resizeStep
            var size = currentFrame.size
            size.width = min(max(size.width + step, options.minimumSize.width), usable.width)
            size.height = min(max(size.height + step, options.minimumSize.height), usable.height)
            var origin = CGPoint(x: currentFrame.midX - size.width / 2, y: currentFrame.midY - size.height / 2)
            origin.x = clamped(origin.x, in: usable.minX...max(usable.minX, usable.maxX - size.width))
            origin.y = clamped(origin.y, in: usable.minY...max(usable.minY, usable.maxY - size.height))
            return CGRect(origin: origin, size: size)
        case .nudgeLeft, .nudgeRight, .nudgeUp, .nudgeDown:
            var origin = currentFrame.origin
            switch placement {
            case .nudgeLeft: origin.x -= options.nudgeDistance
            case .nudgeRight: origin.x += options.nudgeDistance
            case .nudgeUp: origin.y += options.nudgeDistance
            case .nudgeDown: origin.y -= options.nudgeDistance
            default: break
            }
            var size = currentFrame.size
            size.width = min(size.width, usable.width)
            size.height = min(size.height, usable.height)
            origin.x = clamped(origin.x, in: usable.minX...max(usable.minX, usable.maxX - size.width))
            origin.y = clamped(origin.y, in: usable.minY...max(usable.minY, usable.maxY - size.height))
            return CGRect(origin: origin, size: size)
        case .restore, .nextDisplay, .previousDisplay:
            return nil
        }
    }

    private static func clamped(_ value: CGFloat, in range: ClosedRange<CGFloat>) -> CGFloat {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

extension WindowPlacement {
    public var suggestedHotkey: CommandHotkey? {
        let controlOption: UInt32 = 2048 | 4096
        let chord: (UInt32, UInt32, String)? = switch self {
        case .leftHalf: (123, controlOption, "⌃⌥←")
        case .rightHalf: (124, controlOption, "⌃⌥→")
        case .topHalf: (126, controlOption, "⌃⌥↑")
        case .bottomHalf: (125, controlOption, "⌃⌥↓")
        case .topLeft: (32, controlOption, "⌃⌥U")
        case .topRight: (34, controlOption, "⌃⌥I")
        case .bottomLeft: (38, controlOption, "⌃⌥J")
        case .bottomRight: (40, controlOption, "⌃⌥K")
        case .leftThird: (2, controlOption, "⌃⌥D")
        case .centerThird: (3, controlOption, "⌃⌥F")
        case .rightThird: (5, controlOption, "⌃⌥G")
        case .leftTwoThirds: (14, controlOption, "⌃⌥E")
        case .rightTwoThirds: (17, controlOption, "⌃⌥T")
        case .maximize: (36, controlOption, "⌃⌥↩")
        case .almostMaximize: (36, controlOption | 512, "⌃⌥⇧↩")
        case .maximizeHeight: (126, controlOption | 512, "⌃⌥⇧↑")
        case .center: (8, controlOption, "⌃⌥C")
        case .centerHalf: (8, controlOption | 512, "⌃⌥⇧C")
        case .increaseSize: (24, controlOption, "⌃⌥=")
        case .decreaseSize: (27, controlOption, "⌃⌥-")
        case .nextDisplay: (124, controlOption | 256, "⌃⌥⌘→")
        case .previousDisplay: (123, controlOption | 256, "⌃⌥⌘←")
        case .restore: (51, controlOption, "⌃⌥⌫")
        default: nil
        }
        return chord.map { CommandHotkey(keyCode: $0.0, modifiers: $0.1, displayName: $0.2) }
    }

    public var columnSpan: (start: CGFloat, fraction: CGFloat)? {
        switch self {
        case .leftTwoThirds: (0, 2.0 / 3)
        case .centerTwoThirds: (1.0 / 6, 2.0 / 3)
        case .rightTwoThirds: (1.0 / 3, 2.0 / 3)
        case .firstFourth: (0, 0.25)
        case .secondFourth: (0.25, 0.25)
        case .thirdFourth: (0.5, 0.25)
        case .lastFourth: (0.75, 0.25)
        case .firstThreeFourths: (0, 0.75)
        case .lastThreeFourths: (0.25, 0.75)
        case .centerHalf: (0.25, 0.5)
        default: nil
        }
    }
}

public enum WindowDisplayLayout {
    public enum Direction: Sendable { case next, previous }

    public static func nextDisplayIndex(from index: Int, screens: [CGRect], direction: Direction) -> Int? {
        guard screens.indices.contains(index), screens.count > 1 else { return nil }
        let current = screens[index]
        let candidates = screens.indices.filter { candidate in
            guard candidate != index else { return false }
            let screen = screens[candidate]
            let ahead = direction == .next ? screen.midX > current.midX : screen.midX < current.midX
            return ahead && screen.maxY > current.minY && screen.minY < current.maxY
        }
        if let nearest = candidates.min(by: { distance(screens[$0], from: current) < distance(screens[$1], from: current) }) {
            return nearest
        }
        let fallback = screens.indices.filter { $0 != index }
        return direction == .next ? fallback.min(by: { screens[$0].minX < screens[$1].minX }) : fallback.max(by: { screens[$0].maxX < screens[$1].maxX })
    }

    public static func moveFrame(_ frame: CGRect, to visibleFrame: CGRect) -> CGRect {
        let size = CGSize(width: min(frame.width, visibleFrame.width), height: min(frame.height, visibleFrame.height))
        let origin = CGPoint(
            x: clamped(frame.minX, lower: visibleFrame.minX, upper: visibleFrame.maxX - size.width),
            y: clamped(frame.minY, lower: visibleFrame.minY, upper: visibleFrame.maxY - size.height)
        )
        return CGRect(origin: origin, size: size)
    }

    private static func clamped(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), max(lower, upper))
    }

    private static func distance(_ screen: CGRect, from current: CGRect) -> CGFloat {
        abs(screen.midX - current.midX) + abs(screen.midY - current.midY)
    }
}
