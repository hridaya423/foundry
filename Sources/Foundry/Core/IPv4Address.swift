import Foundation

struct IPv4Address: Sendable {
    let octets: (UInt8, UInt8, UInt8, UInt8)

    init?(_ value: String) {
        let parts = value.split(separator: ".")
        let octets = parts.compactMap { UInt8($0) }
        guard parts.count == 4, octets.count == 4 else { return nil }
        self.octets = (octets[0], octets[1], octets[2], octets[3])
    }

    init(_ first: UInt8, _ second: UInt8, _ third: UInt8, _ fourth: UInt8) {
        octets = (first, second, third, fourth)
    }

    var isPublic: Bool {
        switch (octets.0, octets.1) {
        case (0, _), (10, _), (127, _), (169, 254), (192, 168), (172, 16...31), (100, 64...127), (224...255, _):
            return false
        default:
            return true
        }
    }
}
