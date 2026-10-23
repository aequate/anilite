import SwiftUI
import AniliteKit

/// A page's own backdrop: its artwork blurred far past recognition, with the marbled ink in
/// the artwork's colours drifting over it. It stays fixed while content scrolls over it, and
/// when the artwork changes (a new title, the next card) the old one dissolves into the new.
///
/// The image is fetched tiny (the blur hides it) so this costs about as much as a thumbnail.
struct ArtworkBackdrop: View {
    var artwork: String?
    var atmosphere: Atmosphere
    /// How strongly the page shows through. Lower behind dense content.
    var intensity: Double = 0.8

    @Environment(EffectsBudget.self) private var budget

    var body: some View {
        ZStack {
            atmosphere.palette.deepColor
            ZStack {
                if let artwork {
                    BlurredArtwork(url: artwork)
                        .id(artwork)
                        .transition(.opacity)
                }
            }
            .animation(Motion.reveal, value: artwork)

            AtmosphereView(atmosphere: atmosphere, intensity: intensity)
                .opacity(artwork == nil ? 1 : 0.62)

            // Legibility: keep the top lively and settle the lower page towards the ground ink.
            LinearGradient(stops: [
                .init(color: Theme.ink0.opacity(0.10), location: 0),
                .init(color: Theme.ink0.opacity(0.35), location: 0.45),
                .init(color: Theme.ink0.opacity(0.72), location: 1)
            ], startPoint: .top, endPoint: .bottom)
            Theme.ink0.opacity(max(0, 0.8 - intensity) * 0.6)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct BlurredArtwork: View {
    let url: String

    var body: some View {
        GeometryReader { geo in
            RemoteImage(url, points: 120, placeholder: .clear)
                .frame(width: geo.size.width, height: geo.size.height)
                .scaleEffect(1.35)
                .blur(radius: 38, opaque: true)
                .saturation(1.25)
                .opacity(0.7)
        }
        .clipped()
        .drawingGroup()
    }
}

extension Media {
    /// The best small image for a backdrop: the cover, since banners are often missing.
    var backdropArtwork: String? { coverImage?.thumbnail ?? bannerImage }
}
