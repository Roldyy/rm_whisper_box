import SwiftUI

// Reusable UI building blocks matching the redesign mockups.

/// Rounded surface card with hairline border.
struct Card<Content: View>: View {
    var background: Color = Theme.card
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .background(background, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border, lineWidth: 1))
    }
}

/// Uppercase tracked section header (Settings / History groups).
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11.5, weight: .semibold))
            .tracking(0.9)
            .foregroundStyle(Theme.textSecondary)
    }
}

/// Status pill with the mockup's tinted background per state.
struct StatusBadge: View {
    let status: JobStatus
    private var label: String {
        switch status {
        case .running, .pending: return "En cours"
        case .success:           return "Terminé"
        case .error:             return "Erreur"
        case .cancelled:         return "Annulé"
        case .paused:            return "En pause"
        }
    }
    var body: some View {
        let (fg, bg) = Theme.statusColors(status)
        Text(label)
            .font(.system(size: 11.5, weight: .semibold))
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(bg, in: Capsule())
            .foregroundStyle(fg)
    }
}

/// Pill chip with an optional colored dot ("Sortie système", "Micro inclus").
struct Chip: View {
    let label: String
    var dot: Color?
    var body: some View {
        HStack(spacing: 7) {
            if let dot { Circle().fill(dot).frame(width: 6, height: 6) }
            Text(label).font(.system(size: 12.5))
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .foregroundStyle(Color(hex: 0xC7C7CC))
        .background(Theme.chip, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
    }
}

/// Card row with title + subtitle + trailing toggle.
struct ToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14.5)).foregroundStyle(Theme.textPrimary)
                Text(subtitle).font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().tint(Theme.accent)
        }
        .padding(.horizontal, 18).padding(.vertical, 15)
    }
}

// MARK: - Button styles

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 15).padding(.vertical, 8)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.buttonRadius))
            .foregroundStyle(.white)
            .shadow(color: Theme.accent.opacity(0.35), radius: 6, y: 3)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct SecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Theme.control, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
            .foregroundStyle(Theme.bodyText)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct DestructiveButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 5)
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.red.opacity(0.4), lineWidth: 1))
            .foregroundStyle(Theme.redDim)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Decorative red waveform shown while recording.
struct Waveform: View {
    @State private var on = false
    private let count = 46
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(Theme.red.opacity(0.85))
                    .frame(width: 3, height: 6 + 22 * abs(sin(Double(i) * 0.5)))
                    .scaleEffect(y: on ? 1 : 0.35, anchor: .center)
                    .animation(.easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.02), value: on)
            }
        }
        .frame(height: 44)
        .onAppear { on = true }
    }
}

/// Header + scrolling timestamped segment rows. Shared by Record (live) and Transcribe.
struct LivePanel: View {
    let title: String
    var live: Bool = false
    var caption: String = "Texte nettoyé · horodaté par segment"
    let segments: [TranscriptSegment]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 9) {
                    Text(title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    if live {
                        HStack(spacing: 5) {
                            Circle().fill(Theme.green).frame(width: 6, height: 6)
                            Text("en direct").font(.system(size: 11)).foregroundStyle(Theme.green)
                        }
                    }
                }
                Spacer()
                Text(caption).font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Rectangle().fill(Theme.border).frame(height: 1)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(segments) { seg in
                        HStack(alignment: .top, spacing: 14) {
                            Text(timestamp(seg.start))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Theme.accentText)
                                .frame(width: 46, alignment: .leading)
                            Text(seg.text.trimmingCharacters(in: .whitespaces))
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.bodyText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 7)
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 14)
            }
        }
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border, lineWidth: 1))
    }

    private func timestamp(_ s: Double) -> String {
        let i = Int(s); return String(format: "%02d:%02d", i / 60, i % 60)
    }
}

/// The big circular record button from the idle Record screen.
struct RecordButton: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [Color(hex: 0x2D2D31), Color(hex: 0x202022)],
                        center: UnitPoint(x: 0.5, y: 0.36), startRadius: 2, endRadius: 70))
                    .frame(width: 112, height: 112)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
                    .shadow(color: .black.opacity(0.45), radius: 17, y: 12)
                Circle()
                    .fill(Theme.red)
                    .frame(width: 40, height: 40)
                    .overlay(Circle().strokeBorder(Theme.red.opacity(0.13), lineWidth: 7).frame(width: 54, height: 54))
            }
        }
        .buttonStyle(.plain)
    }
}
