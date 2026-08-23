import Photos
import SwiftUI

struct SwipeCardView: View {
    let asset: PHAsset
    let manager: PHCachingImageManager
    let isInteractive: Bool
    @Binding var requestedDecision: SwipeDecision?
    let onDecision: (SwipeDecision) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGSize = .zero
    @State private var isExiting = false
    @State private var showingDetail = false

    var body: some View {
        interactiveCard
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("写真カード")
            .accessibilityHint("左で削除候補、右でキープ、上でお気に入り")
            .accessibilityAction(named: "削除候補へ") { exit(.trash) }
            .accessibilityAction(named: "キープ") { exit(.keep) }
            .accessibilityAction(named: "お気に入り") { exit(.favorite) }
            .accessibilityAction(named: "写真を拡大") { showingDetail = true }
            .onChange(of: requestedDecision) { _, decision in if let decision { exit(decision) } }
            .fullScreenCover(isPresented: $showingDetail) {
                PhotoDetailView(asset: asset, manager: manager)
            }
    }

    private var interactiveCard: some View {
        movingCard
            .gesture(dragGesture, including: isInteractive ? .all : .none)
            .simultaneousGesture(cardTapGesture)
            .allowsHitTesting(isInteractive && !isExiting)
    }

    private var movingCard: some View {
        styledCard
            .offset(offset)
            .rotationEffect(.degrees(Double(offset.width / 24)))
    }

    private var styledCard: some View {
        AssetImageView(asset: asset, manager: manager, displayMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(alignment: stampAlignment) { stamp }
            .overlay { RoundedRectangle(cornerRadius: 26).stroke(Color.swipeeBorder, lineWidth: 1) }
            .shadow(color: .black.opacity(0.15), radius: 18, y: 9)
    }

    private var cardTapGesture: some Gesture {
        TapGesture().onEnded {
            if isInteractive && !isExiting {
                showingDetail = true
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { offset = $0.translation }
            .onEnded { value in
                if let decision = decision(for: value) { exit(decision) }
                else { withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.72)) { offset = .zero } }
            }
    }

    private func decision(for value: DragGesture.Value) -> SwipeDecision? {
        let predicted = value.predictedEndTranslation
        if predicted.height < -110, abs(predicted.height) > abs(predicted.width) { return .favorite }
        if predicted.width < -110 { return .trash }
        if predicted.width > 110 { return .keep }
        return nil
    }

    private func exit(_ decision: SwipeDecision) {
        guard isInteractive, !isExiting else { return }
        isExiting = true
        let destination: CGSize = switch decision {
        case .trash: CGSize(width: -700, height: offset.height * 0.25)
        case .keep: CGSize(width: 700, height: offset.height * 0.25)
        case .favorite: CGSize(width: offset.width * 0.2, height: -900)
        }
        withAnimation(reduceMotion ? nil : .easeIn(duration: 0.25)) { offset = destination }
        Task {
            if !reduceMotion { try? await Task.sleep(for: .milliseconds(250)) }
            await MainActor.run { requestedDecision = nil; onDecision(decision); offset = .zero; isExiting = false }
        }
    }

    @ViewBuilder private var stamp: some View {
        let data: (String, Color)? = {
            if offset.height < -55, abs(offset.height) > abs(offset.width) { return ("お気に入り", .swipeeFavorite) }
            if offset.width < -55 { return ("削除候補", .swipeeDelete) }
            if offset.width > 55 { return ("キープ", .swipeeKeep) }
            return nil
        }()
        if let data {
            Text(data.0).font(.title2).fontWeight(.black).foregroundStyle(data.1).padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.swipeePhotoOverlay, in: RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).stroke(data.1, lineWidth: 4) }.rotationEffect(.degrees(-10)).padding(24)
        }
    }
    private var stampAlignment: Alignment { offset.width < 0 ? .topTrailing : .topLeading }
}
