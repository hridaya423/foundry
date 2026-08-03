import Foundation

struct FoundryPollingPolicy: Equatable, Sendable {
    let metricsInterval: Duration
    let networkInterval: Duration
    let downloadsInterval: Duration
    let agentsInterval: Duration

    static func make(isLowPowerModeEnabled: Bool, thermalState: ProcessInfo.ThermalState) -> Self {
        let constrained = isLowPowerModeEnabled || thermalState == .serious || thermalState == .critical
        if thermalState == .critical {
            return Self(
                metricsInterval: .seconds(20),
                networkInterval: .seconds(1_800),
                downloadsInterval: .seconds(300),
                agentsInterval: .seconds(180)
            )
        }
        if constrained {
            return Self(
                metricsInterval: .seconds(6),
                networkInterval: .seconds(1_200),
                downloadsInterval: .seconds(180),
                agentsInterval: .seconds(120)
            )
        }
        return Self(
            metricsInterval: .seconds(2),
            networkInterval: .seconds(600),
            downloadsInterval: .seconds(60),
            agentsInterval: .seconds(60)
        )
    }

    static var current: Self {
        make(
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermalState: ProcessInfo.processInfo.thermalState
        )
    }
}
