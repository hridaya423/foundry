import XCTest
@testable import Foundry

final class SystemMetricsTests: XCTestCase {
    func testMetricNeedsCanSkipExpensiveMeasurements() {
        let sampler = SystemMetricsSampler()

        let metrics = sampler.sample(needs: [])

        XCTAssertEqual(metrics.cpuPercent, 0)
        XCTAssertEqual(metrics.memoryUsed, 0)
        XCTAssertEqual(metrics.loadAverage1m, 0)
    }

    func testMetricNeedsCanRequestOnlyCPUAndMemory() {
        let sampler = SystemMetricsSampler()

        let metrics = sampler.sample(needs: [.cpu, .memory])

        XCTAssertGreaterThan(metrics.memoryTotal, 0)
        XCTAssertEqual(metrics.batteryPercent, nil)
        XCTAssertEqual(metrics.diskTotalBytes, 0)
        XCTAssertNil(metrics.localIPAddress)
        XCTAssertEqual(metrics.loadAverage1m, 0)
    }

    func testPollingPolicySlowsDownForLowPowerAndThermalPressure() {
        let normal = FoundryPollingPolicy.make(isLowPowerModeEnabled: false, thermalState: .nominal)
        let lowPower = FoundryPollingPolicy.make(isLowPowerModeEnabled: true, thermalState: .nominal)
        let critical = FoundryPollingPolicy.make(isLowPowerModeEnabled: false, thermalState: .critical)

        XCTAssertEqual(normal.metricsInterval, .seconds(2))
        XCTAssertEqual(lowPower.metricsInterval, .seconds(6))
        XCTAssertGreaterThan(critical.metricsInterval, lowPower.metricsInterval)
        XCTAssertGreaterThan(critical.downloadsInterval, lowPower.downloadsInterval)
    }
}
