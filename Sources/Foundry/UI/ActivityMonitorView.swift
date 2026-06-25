import AppKit
import SwiftUI

struct ActivityMonitorView: View {
    @ObservedObject var state: ActivityMonitorState

    var body: some View {
        HStack(spacing: 0) {
            processList

            Rectangle()
                .fill(FoundryTheme.border.opacity(0.65))
                .frame(width: 1)

            detailPane
        }
        .background(Color.clear)
    }

    private var processList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Activity Monitor")
                .font(FoundryTheme.body(size: 11, weight: .semibold))
                .foregroundStyle(FoundryTheme.faintText)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 16)
                .padding(.top, 12)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 3) {
                        overviewRow
                            .id(Int32.min)

                        ForEach(state.visibleGroups) { group in
                            ActivityProcessGroupRow(
                                group: group,
                                isSelected: state.selectedGroupID == group.id,
                                showCPU: state.hasStableCPUSample
                            )
                            .id(group.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                state.select(groupID: group.id)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.never)
                .onChange(of: state.selectedGroupID) { _, groupID in
                    guard let groupID else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(groupID, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 278)
    }

    private var overviewRow: some View {
        HStack(spacing: 12) {
            ActivitySymbolIcon(systemName: "cpu")

            VStack(alignment: .leading, spacing: 3) {
                Text("Overview")
                    .font(FoundryTheme.body(size: 14, weight: .semibold))
                    .foregroundStyle(FoundryTheme.primaryText)

                Text("\(state.snapshot.processCount) processes - \(state.snapshot.groupCount) groups")
                    .font(FoundryTheme.body(size: 12, weight: .regular))
                    .foregroundStyle(FoundryTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            Text(cpuLabel)
                .font(FoundryTheme.body(size: 12, weight: .semibold))
                .foregroundStyle(FoundryTheme.secondaryText)
        }
        .padding(.horizontal, 10)
        .frame(height: 56)
        .background(Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var detailPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                detailHeader
                overviewCards
                ActivityHistoryCard(title: "CPU Pressure", value: cpuLabel, samples: state.cpuHistory, tint: Color.white.opacity(0.86))
                ActivityHistoryCard(title: "Memory Pressure", value: memorySummary, samples: state.memoryHistory, tint: Color.cyan.opacity(0.82))
                selectedGroupCard
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .scrollIndicators(.never)
    }

    private var detailHeader: some View {
        HStack(spacing: 12) {
            ActivitySymbolIcon(systemName: "cpu")

            VStack(alignment: .leading, spacing: 3) {
                Text("Overview")
                    .font(FoundryTheme.body(size: 17, weight: .semibold))
                    .foregroundStyle(FoundryTheme.primaryText)

                Text("\(state.snapshot.processCount) processes - \(state.snapshot.groupCount) groups")
                    .font(FoundryTheme.body(size: 13, weight: .regular))
                    .foregroundStyle(FoundryTheme.secondaryText)
            }

            Spacer()

            Button(action: state.refreshNow) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FoundryTheme.secondaryText)
            }
            .buttonStyle(.plain)
            .pointerCursor()
        }
    }

    private var overviewCards: some View {
        HStack(spacing: 8) {
            ActivityMetricCard(title: "Memory", value: bytes(state.snapshot.memoryUsed), subtitle: percent(memoryPercent))
            ActivityMetricCard(title: "CPU", value: cpuLabel, subtitle: "system total")
            ActivityMetricCard(title: "Processes", value: "\(state.snapshot.processCount)", subtitle: "processes")
            ActivityMetricCard(title: "Visible", value: "\(state.visibleGroups.count)", subtitle: "groups")
        }
    }

    @ViewBuilder
    private var selectedGroupCard: some View {
        if let group = state.selectedGroup {
            VStack(alignment: .leading, spacing: 12) {
                Text("Selected Group")
                    .font(FoundryTheme.body(size: 14, weight: .semibold))
                    .foregroundStyle(FoundryTheme.primaryText)

                HStack(spacing: 12) {
                    ActivityProcessIcon(path: group.iconPath, symbolName: group.symbolName, fallback: group.displayName)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.displayName)
                            .font(FoundryTheme.body(size: 15, weight: .semibold))
                            .foregroundStyle(FoundryTheme.primaryText)
                            .lineLimit(1)

                        if let path = group.primaryPath {
                            Text(path)
                                .font(FoundryTheme.body(size: 11, weight: .regular))
                                .foregroundStyle(FoundryTheme.secondaryText)
                                .lineLimit(1)
                        } else {
                            Text(group.subtitle)
                                .font(FoundryTheme.body(size: 11, weight: .regular))
                                .foregroundStyle(FoundryTheme.secondaryText)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(bytes(group.memoryBytes))
                            .font(FoundryTheme.body(size: 14, weight: .semibold))
                            .foregroundStyle(FoundryTheme.primaryText)

                        Text(cpuLabel(for: group))
                            .font(FoundryTheme.body(size: 12, weight: .regular))
                            .foregroundStyle(FoundryTheme.secondaryText)
                    }
                }

                VStack(spacing: 0) {
                    ForEach(group.processes.prefix(4)) { process in
                        HStack(spacing: 8) {
                            Text("\(process.pid)")
                                .font(FoundryTheme.mono(size: 11, weight: .semibold))
                                .foregroundStyle(FoundryTheme.mutedText)
                                .frame(width: 46, alignment: .leading)

                            Text(process.name)
                                .font(FoundryTheme.body(size: 12, weight: .medium))
                                .foregroundStyle(FoundryTheme.secondaryText)
                                .lineLimit(1)

                            Spacer()

                            Text(bytes(process.memoryBytes))
                                .font(FoundryTheme.mono(size: 11, weight: .semibold))
                                .foregroundStyle(FoundryTheme.secondaryText)
                        }
                        .frame(height: 24)
                    }
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.060))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private var memoryPercent: Double {
        state.snapshot.memoryTotal == 0 ? 0 : Double(state.snapshot.memoryUsed) / Double(state.snapshot.memoryTotal) * 100
    }

    private var memorySummary: String {
        "\(bytes(state.snapshot.memoryUsed)) / \(bytes(state.snapshot.memoryTotal))"
    }

    private var cpuLabel: String {
        state.hasStableCPUSample ? percent(state.snapshot.cpuUsage) : "sampling"
    }

    private func cpuLabel(for group: ActivityProcessGroup) -> String {
        guard state.hasStableCPUSample, group.hasCPUReading else { return "sampling" }
        return activityCPUText(group.cpuUsage, hasReading: group.hasCPUReading)
    }

    private func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }
}

private func activityCPUText(_ value: Double, hasReading: Bool) -> String {
    guard hasReading else { return "sampling" }
    if value <= 0.0001 { return "idle" }
    if value < 0.1 { return "<0.1%" }
    if value >= 10 { return "\(Int(value.rounded()))%" }
    return String(format: "%.1f%%", value)
}

private struct ActivityProcessGroupRow: View {
    let group: ActivityProcessGroup
    let isSelected: Bool
    let showCPU: Bool

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 11) {
            ActivityProcessIcon(path: group.iconPath, symbolName: group.symbolName, fallback: group.displayName)

            VStack(alignment: .leading, spacing: 3) {
                Text(group.displayName)
                    .font(FoundryTheme.body(size: 14, weight: .semibold))
                    .foregroundStyle(FoundryTheme.primaryText)
                    .lineLimit(1)

                Text(group.subtitle)
                    .font(FoundryTheme.body(size: 11, weight: .regular))
                    .foregroundStyle(FoundryTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(ByteCountFormatter.string(fromByteCount: Int64(group.memoryBytes), countStyle: .memory))
                    .font(FoundryTheme.body(size: 12, weight: .semibold))
                    .foregroundStyle(FoundryTheme.primaryText)
                    .monospacedDigit()

                Text(showCPU ? activityCPUText(group.cpuUsage, hasReading: group.hasCPUReading) : "--")
                    .font(FoundryTheme.body(size: 10, weight: .semibold))
                    .foregroundStyle(FoundryTheme.mutedText)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 54)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? FoundryTheme.selection : (isHovering ? FoundryTheme.hover : Color.clear))
        )
        .animation(.easeOut(duration: 0.10), value: isSelected)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }
}

private struct ActivityMetricCard: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(FoundryTheme.body(size: 11, weight: .semibold))
                .foregroundStyle(FoundryTheme.secondaryText)

            Text(value)
                .font(FoundryTheme.body(size: 18, weight: .bold))
                .foregroundStyle(FoundryTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(subtitle)
                .font(FoundryTheme.body(size: 11, weight: .semibold))
                .foregroundStyle(FoundryTheme.mutedText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(Color.white.opacity(0.070))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct ActivityHistoryCard: View {
    let title: String
    let value: String
    let samples: [Double]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(FoundryTheme.body(size: 13, weight: .semibold))
                    .foregroundStyle(FoundryTheme.primaryText)

                Spacer()

                Text(value)
                    .font(FoundryTheme.body(size: 12, weight: .semibold))
                    .foregroundStyle(FoundryTheme.secondaryText)
            }

            ZStack {
                VStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.white.opacity(0.055))
                            .frame(height: 1)
                        Spacer(minLength: 0)
                    }
                }

                ActivityArea(samples: samples)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.30), tint.opacity(0.035)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                ActivitySparkline(samples: samples)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    .shadow(color: tint.opacity(0.28), radius: 6, x: 0, y: 2)
            }
            .frame(height: 68)
        }
        .padding(13)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.070), tint.opacity(0.035), Color.white.opacity(0.045)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct ActivitySparkline: Shape {
    let samples: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard samples.isEmpty == false else {
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }

        let maxValue = 100.0
        for (index, sample) in samples.enumerated() {
            let x = rect.minX + CGFloat(index) / CGFloat(max(samples.count - 1, 1)) * rect.width
            let normalized = min(max(sample / maxValue, 0), 1)
            let y = rect.maxY - CGFloat(normalized) * rect.height
            let point = CGPoint(x: x, y: y)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}

private struct ActivityArea: Shape {
    let samples: [Double]

    func path(in rect: CGRect) -> Path {
        var path = ActivitySparkline(samples: samples).path(in: rect)
        guard samples.isEmpty == false else { return path }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct ActivityProcessIcon: View {
    let path: String?
    let symbolName: String?
    let fallback: String

    var body: some View {
        Group {
            if let path {
                Image(nsImage: ActivityIconCache.shared.icon(forFile: path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if let symbolName {
                ActivitySymbolIcon(systemName: symbolName)
            } else {
                ActivitySymbolIcon(systemName: "cpu")
            }
        }
        .frame(width: 34, height: 34)
    }
}

private struct ActivitySymbolIcon: View {
    let systemName: String

    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color.white.opacity(0.085))
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(FoundryTheme.secondaryText)
            )
            .frame(width: 34, height: 34)
    }
}

@MainActor
private final class ActivityIconCache {
    static let shared = ActivityIconCache()

    private let cache = NSCache<NSString, NSImage>()

    func icon(forFile path: String) -> NSImage {
        let key = path as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 34, height: 34)
        cache.setObject(image, forKey: key)
        return image
    }
}
