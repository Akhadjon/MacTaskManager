import SwiftUI
import AppKit

// MARK: - Metric accent colors

extension PerformanceMetric {
    var accentColor: Color {
        switch self {
        case .cpu:     return .blue
        case .memory:  return .green
        case .network: return Color(red: 1.0, green: 0.45, blue: 0.1)  // orange
        case .disk:    return Color(red: 0.6, green: 0.3, blue: 0.9)   // purple
        }
    }
}

// MARK: - Line / Area Chart

struct SparklineChart: View {
    var data: [Double]
    var color: Color
    var maxValue: Double
    var showFill: Bool = true

    var body: some View {
        Canvas { ctx, size in
            guard data.count > 1 else { return }
            let maxV = max(maxValue, data.max() ?? 1, 1e-9)

            let pts: [CGPoint] = data.enumerated().map { i, v in
                let x = size.width  * CGFloat(i) / CGFloat(data.count - 1)
                let y = size.height * (1 - CGFloat(safeDouble(v) / maxV))
                return CGPoint(x: x, y: max(0, min(size.height, y)))
            }

            // Fill
            if showFill {
                var fill = Path()
                fill.move(to: CGPoint(x: pts[0].x, y: size.height))
                for p in pts { fill.addLine(to: p) }
                fill.addLine(to: CGPoint(x: pts.last!.x, y: size.height))
                fill.closeSubpath()
                ctx.fill(fill, with: .color(color.opacity(0.18)))
            }

            // Line
            var line = Path()
            line.move(to: pts[0])
            for p in pts.dropFirst() { line.addLine(to: p) }
            ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
        .animation(.none, value: data.count)
    }
}

// MARK: - Metric Card (summary tile at top)

struct MetricCard: View {
    var title: String
    var value: String
    var subtitle: String?
    var color: Color
    var history: [Double]
    var historyMax: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if !history.isEmpty {
                SparklineChart(data: history, color: color, maxValue: historyMax)
                    .frame(height: 32)
            }
            if let sub = subtitle {
                Text(sub)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    var cardBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Stat Tile (compact key/value)

struct StatTile: View {
    var label: String
    var value: String
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    var title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .tracking(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Top Process Row

struct TopProcessRow: View {
    var rank: Int
    var process: ProcessRow
    var value: String
    var color: Color

    var body: some View {
        HStack(spacing: 8) {
            Text("\(rank)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 14, alignment: .trailing)

            ProcessIconView(icon: process.icon, size: 16)

            Text(process.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Process Icon

struct ProcessIconView: View {
    var icon: NSImage?
    var size: CGFloat = 20

    var body: some View {
        if let img = icon {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "app")
                .resizable()
                .frame(width: size, height: size)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Large Chart Panel

struct LargeChartPanel: View {
    var title: String
    var data: [Double]
    var maxValue: Double
    var color: Color
    var leftLabel: String
    var rightLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("60s")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.windowBackgroundColor))
                SparklineChart(data: data.isEmpty ? [0] : data,
                               color: color,
                               maxValue: maxValue)
                    .padding(4)
                VStack {
                    HStack {
                        Spacer()
                        Text(rightLabel)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(4)
                    }
                    Spacer()
                    HStack {
                        Text(leftLabel)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(4)
                        Spacer()
                    }
                }
            }
            .frame(height: 100)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Panel Container

struct Panel<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            content()
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Inline Notice Banner

struct NoticeBanner: View {
    var message: String
    var isSuccess: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(isSuccess ? .green : .red)
            Text(message)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            (isSuccess ? Color.green : Color.red).opacity(0.12)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke((isSuccess ? Color.green : Color.red).opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - Left Navigation Rail Item

struct NavRailItem: View {
    var section: AppSection
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.systemIcon)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .frame(width: 20)
                Text(section.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                Spacer()
            }
            .foregroundColor(isSelected ? .accentColor : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color.accentColor.opacity(0.15))
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings Sheet

struct SettingsSheetView: View {
    @EnvironmentObject var store: MonitorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.title2)
                .fontWeight(.semibold)

            GroupBox("Appearance") {
                Picker("", selection: Binding(
                    get:  { store.appearance },
                    set:  { store.setAppearance($0) }
                )) {
                    ForEach(AppearanceSetting.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 4)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") { store.showingSettings = false }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 340, height: 180)
    }
}
