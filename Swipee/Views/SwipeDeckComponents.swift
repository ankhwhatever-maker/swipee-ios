import SwiftUI

struct SwipeDeckBackground: View {
    let activeDecision: SwipeDecision?
    let isDeckVisible: Bool
    let reduceMotion: Bool

    var body: some View {
        background
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: activeDecision)
    }

    private var background: LinearGradient {
        guard isDeckVisible else {
            return LinearGradient(
                colors: [.swipeeBackground, .swipeeBackground],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        switch activeDecision {
        case .trash:
            return LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.05, blue: 0.12),
                    Color(red: 0.24, green: 0.15, blue: 0.34)
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
        case .keep:
            return LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.10, blue: 0.06),
                    Color(red: 0.10, green: 0.31, blue: 0.20)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            let restingColor = Color(red: 0.043, green: 0.043, blue: 0.051)
            return LinearGradient(
                colors: [restingColor, restingColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

struct SwipeActionControls: View {
    let activeDecision: SwipeDecision?
    let isProcessing: Bool
    let canUndo: Bool
    let onDelete: () -> Void
    let onKeep: () -> Void
    let onUndo: () -> Void

    var body: some View {
        ZStack {
            HStack(spacing: 32) {
                actionButton("削除", color: .swipeeDelete, decision: .trash, action: onDelete)
                actionButton("キープ", color: .swipeeKeep, decision: .keep, action: onKeep)
            }
            HStack {
                undoButton
                    .opacity(activeDecision == nil ? 1 : 0)
                    .scaleEffect(activeDecision == nil ? 1 : 0.72)
                Spacer()
            }
        }
    }

    private var undoButton: some View {
        Button(action: onUndo) {
            Image(systemName: "arrow.uturn.backward")
                .font(.subheadline.bold())
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.12), in: Circle())
                .overlay { Circle().stroke(.white.opacity(0.2)) }
                .frame(width: 44, height: 44)
        }
        .foregroundStyle(.white.opacity(0.82))
        .opacity(canUndo ? 1 : 0.28)
        .disabled(isProcessing || !canUndo)
        .accessibilityLabel("直前の操作を戻す")
        .accessibilityHint("直前に操作した写真をカードへ戻します")
    }

    private func actionButton(
        _ title: String,
        color: Color,
        decision: SwipeDecision,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline.bold())
                .frame(width: 86, height: 54)
                .background(.white.opacity(0.12), in: Capsule())
                .overlay { Capsule().stroke(.white.opacity(0.2)) }
                .foregroundStyle(color)
        }
        .scaleEffect(activeDecision == decision ? 1.28 : 1)
        .opacity(activeDecision == nil || activeDecision == decision ? 1 : 0)
        .disabled(isProcessing)
        .accessibilityLabel(title)
    }
}

enum CardRestorationAnimation {
    @MainActor
    static func run(progress: Binding<CGFloat>, reduceMotion: Bool) async {
        progress.wrappedValue = 0

        // Place the card offscreen for one render pass before bringing it home.
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(16))
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.18)) {
                progress.wrappedValue = 1
            }
            try? await Task.sleep(for: .milliseconds(180))
        } else {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                progress.wrappedValue = 1
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    static func offset(
        for decision: SwipeDecision?,
        progress: CGFloat,
        in size: CGSize,
        reduceMotion: Bool
    ) -> CGSize {
        guard let decision, !reduceMotion else { return .zero }
        let remaining = 1 - progress
        switch decision {
        case .trash:
            return CGSize(width: -max(size.width * 1.15, 420) * remaining, height: 18 * remaining)
        case .keep:
            return CGSize(width: max(size.width * 1.15, 420) * remaining, height: 18 * remaining)
        case .favorite:
            return CGSize(width: 0, height: -max(size.height * 1.15, 620) * remaining)
        }
    }

    static func rotation(
        for decision: SwipeDecision?,
        progress: CGFloat,
        reduceMotion: Bool
    ) -> Angle {
        guard let decision, !reduceMotion else { return .zero }
        let remaining = 1 - progress
        switch decision {
        case .trash: return .degrees(-10 * remaining)
        case .keep: return .degrees(10 * remaining)
        case .favorite: return .zero
        }
    }
}

extension View {
    func cardRestorationEffect(
        decision: SwipeDecision?,
        progress: CGFloat,
        availableSize: CGSize,
        reduceMotion: Bool
    ) -> some View {
        offset(
            CardRestorationAnimation.offset(
                for: decision,
                progress: progress,
                in: availableSize,
                reduceMotion: reduceMotion
            )
        )
        .rotationEffect(
            CardRestorationAnimation.rotation(
                for: decision,
                progress: progress,
                reduceMotion: reduceMotion
            )
        )
        .opacity(decision != nil && reduceMotion ? progress : 1)
        .accessibilityHidden(decision != nil)
    }
}
