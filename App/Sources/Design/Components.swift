import SwiftUI
import UIKit
import AniliteKit

// MARK: - Haptics

/// Haptics with meaning: light ticks for scrubbing, success for completions, a heavier
/// thud when something snaps into place. Disabled from Settings.
@MainActor
enum Haptics {
    static var enabled = true

    static func tick() {
        guard enabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light, intensity: CGFloat = 1) {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred(intensity: intensity)
    }

    static func success() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func error() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

// MARK: - Buttons

/// Press feedback for cards and rows: a slight sink, no spring.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.975

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

/// Primary action. Washi paper on ink by default; on a title's own screen it takes that
/// title's colour, with text contrast chosen from the fill.
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.textPrimary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.ink0)
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .frame(minHeight: 48)
            .background(tint, in: RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

/// Secondary action: an outlined button that leaves the page's colour alone.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .frame(minHeight: 44)
            .background(configuration.isPressed ? Theme.ink2 : Theme.ink1, in: shape)
            .overlay(shape.strokeBorder(Theme.rule, lineWidth: 1))
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

// MARK: - Chips

struct Chip: View {
    var label: String
    var symbol: String?
    var isSelected = false
    var tint: Color = Theme.textPrimary

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol).font(.caption.weight(.bold))
            }
            Text(label).font(.subheadline.weight(.semibold)).lineLimit(1)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .frame(minHeight: 36)
        .foregroundStyle(isSelected ? Theme.ink0 : Theme.textPrimary)
        .background {
            if isSelected {
                Capsule().fill(tint)
            } else {
                Capsule().fill(Theme.ink1)
                    .overlay(Capsule().strokeBorder(Theme.rule))
            }
        }
        .animation(Motion.quick, value: isSelected)
        .contentShape(Capsule())
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

/// Wrapping layout for chips and tags.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Progress

struct ProgressRing: View {
    var progress: Double
    var tint: Color = Theme.accent
    var lineWidth: CGFloat = 4

    var body: some View {
        ZStack {
            Circle().stroke(Theme.ink3, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamp01(progress))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(Motion.gentle, value: progress)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((clamp01(progress) * 100).rounded())) percent")
    }
}

struct ProgressBar: View {
    var progress: Double
    var tint: Color = Theme.accent
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.ink3)
                Capsule().fill(tint).frame(width: max(height, proxy.size.width * clamp01(progress)))
            }
        }
        .frame(height: height)
        .animation(Motion.gentle, value: progress)
        .accessibilityHidden(true)
    }
}

// MARK: - Section header

struct SectionHeader<Trailing: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Typo.sectionTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).font(.footnote).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = { EmptyView() }
    }
}

// MARK: - States

struct EmptyStateView: View {
    var symbol: String
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)
            Text(title).font(Typo.sectionTitle).foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct ErrorBanner: View {
    var message: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.caution)
                .accessibilityHidden(true)
            Text(message)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let retry {
                Button("Retry", action: retry)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(14)
        .surface(cornerRadius: Theme.cornerSmall, tint: Theme.caution)
        .padding(.horizontal, Theme.gutter)
        .accessibilityElement(children: .combine)
    }
}

/// Placeholder block while content loads: a flat surface in the shape of what's coming.
struct Skeleton: View {
    var cornerRadius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: min(cornerRadius, Theme.corner), style: .continuous)
            .fill(Theme.ink1)
            .accessibilityHidden(true)
    }
}

/// Small pill showing a stat, e.g. "★ 86%".
struct StatPill: View {
    var symbol: String
    var text: String
    var tint: Color = Theme.textSecondary

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.caption2.weight(.bold)).foregroundStyle(tint)
            Text(text).font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.ink0.opacity(0.72), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
