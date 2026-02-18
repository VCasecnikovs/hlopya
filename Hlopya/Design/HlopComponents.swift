import SwiftUI

// MARK: - Glass Card

/// Reusable glass container with optional tint color
struct GlassCard<Content: View>: View {
    var tint: Color?
    var cornerRadius: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill((tint ?? .clear).opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(.white.opacity(0.15), lineWidth: 0.5)
                    )
            }
    }
}

// MARK: - Section Header

/// Unified section header with optional icon
struct SectionHeader: View {
    let title: String
    var icon: String?

    var body: some View {
        HStack(spacing: HlopSpacing.xs) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(1)
                .textCase(.uppercase)
        }
    }
}

// MARK: - Glass Pill Badge

/// Mini glass pill for status indicators
struct GlassBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .fill(color.opacity(0.12))
                    )
                    .overlay(
                        Capsule()
                            .stroke(color.opacity(0.2), lineWidth: 0.5)
                    )
            )
            .foregroundStyle(color)
    }
}

// MARK: - Shimmer Effect

/// Subtle shimmer overlay for glass elements during recording
struct ShimmerEffect: ViewModifier {
    let isActive: Bool
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive {
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.06), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .offset(x: phase)
                    .onAppear {
                        withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                            phase = 300
                        }
                    }
                    .mask(content)
                }
            }
    }
}

extension View {
    func shimmer(isActive: Bool) -> some View {
        modifier(ShimmerEffect(isActive: isActive))
    }
}

// MARK: - Empty State

/// Reusable empty state with icon, message, and optional CTA
struct EmptyStateView: View {
    let icon: String
    let title: String
    var subtitle: String?
    var buttonTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: HlopSpacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
                .symbolEffect(.pulse.byLayer, options: .repeating.speed(0.5))

            VStack(spacing: HlopSpacing.xs) {
                Text(title)
                    .font(HlopTypography.title3)
                    .foregroundStyle(.secondary)

                if let subtitle {
                    Text(subtitle)
                        .font(HlopTypography.body)
                        .foregroundStyle(.tertiary)
                }
            }

            if let buttonTitle, let action {
                Button(action: action) {
                    Text(buttonTitle)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Inline Error Card

/// Inline error card with retry button (replaces alerts for non-critical errors)
struct InlineErrorCard: View {
    let message: String
    var onRetry: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: HlopSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(HlopColors.statusWarning)
                .font(.system(size: 13))

            Text(message)
                .font(HlopTypography.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Spacer(minLength: 0)

            if let onRetry {
                Button("Retry", action: onRetry)
                    .controlSize(.small)
                    .buttonStyle(.bordered)
            }

            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(HlopSpacing.md)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(HlopColors.statusWarning.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(HlopColors.statusWarning.opacity(0.15), lineWidth: 0.5)
                )
        }
    }
}

// MARK: - Processing Progress

/// Multi-stage processing progress indicator
struct ProcessingProgress: View {
    let stage: String
    var progress: Double?

    var body: some View {
        VStack(spacing: HlopSpacing.sm) {
            if let progress {
                ProgressView(value: progress)
                    .tint(HlopColors.statusProcessing)
            } else {
                ProgressView()
                    .controlSize(.small)
            }

            Text(stage)
                .font(HlopTypography.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
