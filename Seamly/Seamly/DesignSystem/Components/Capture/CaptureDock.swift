import SwiftUI
import PhotosUI

/// Return-home IA: the capture affordance is PERMANENTLY present, never a toolbar icon.
/// Docked at the bottom, in thumb reach, with the two import paths flanking it so the hero is
/// unmistakable but the alternatives cost one tap.
///
/// The centre is `BroadcastPickerButton` rather than a `Button`, because
/// `RPSystemBroadcastPickerView` has no SwiftUI equivalent and is the project's one sanctioned
/// UIKit exception. It draws a fixed **black** glyph in both appearances and does not adapt, so
/// the accent slab behind it carries the contrast on its own, exactly as `HomeView`'s disc did.
///
/// **The two side buttons open their picker directly.** They used to push an `ImportSheet` whose
/// only content was a second tappable row, so reaching the photo library cost two taps and a
/// modal for one decision. `PhotosPicker` opens the library by making *its label* the button, so
/// the picker now lives inside the side button itself (`ImportTrigger`) and the sheet is gone.
///
/// Width is capped: a 1024 pt-wide capture button on iPad is absurd.
///
/// When live capture cannot work on this device (`LiveCaptureAvailability`), the hero's slot
/// carries the sentence saying so instead of the picker. A Record button with nothing behind it
/// swallows the tap in silence, and App Review read that silence as functionality hidden from
/// them (guideline 5.6). The two import paths stay either side of the sentence, because they are
/// exactly what it tells the user to use.
struct CaptureDock: View {
    var liveCapture: LiveCaptureAvailability = .available
    var recording: Bool = false
    /// The state the pickers write into. Owned by `AppShell`, because the same selection drives
    /// the import in whichever screen the dock happens to be on.
    @Binding var videoSelection: PhotosPickerItem?
    @Binding var photoSelection: [PhotosPickerItem]

    var body: some View {
        HStack(spacing: SeamlySpace.s4) {
            ImportTrigger(
                source: .video,
                videoSelection: $videoSelection,
                photoSelection: $photoSelection,
                symbol: "film",
                label: "导入录屏"
            )
            if let explanation = liveCapture.explanation {
                Text(explanation)
                    .font(SeamlyFont.footnote)
                    .foregroundStyle(SeamlyColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .accessibilityIdentifier("record-unavailable")
            } else {
                recordSlab
            }
            ImportTrigger(
                source: .photos,
                videoSelection: $videoSelection,
                photoSelection: $photoSelection,
                symbol: "photo.on.rectangle",
                label: "导入截图"
            )
        }
        .frame(maxWidth: SeamlySpace.columnMax)
        .frame(maxWidth: .infinity)
    }

    private var recordSlab: some View {
        ZStack {
            // The picker is at the BOTTOM of the stack at full opacity, and our own slab is
            // painted opaque on top of it. It must NOT be faded to hide it: SwiftUI declines
            // to route touches into a near-transparent `UIViewRepresentable` host, so the
            // `.opacity(0.02)` this used to carry silently ate every tap — UIKit's own
            // `hitTest` still returned the picker's private `UIButton` (0.02 clears UIKit's
            // documented 0.01 alpha floor), so the view looked correct from every angle
            // except the only one that mattered. Occlusion costs nothing: z-order does not
            // affect hit-testing, `allowsHitTesting(false)` on the covers lets the touch
            // fall through, and there is no undocumented threshold left to sit near.
            //
            // Must fill the slab. `RPSystemBroadcastPickerView` reports a small intrinsic
            // size, and a ZStack child without its own flexible frame is laid out at that
            // size and centred — which would leave the hero button tappable only in a
            // circle at its middle, with dead zones either side.
            //
            // We present the picker as-is; reaching into its private subviews to restyle or
            // auto-tap it is the fragility we refuse.
            BroadcastPickerButton()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(recording ? "录制中" : "录制")
                .accessibilityIdentifier("record-button")
            RoundedRectangle(cornerRadius: SeamlyRadius.sm, style: .continuous)
                .fill(recording ? SeamlyColor.markRec : SeamlyColor.accent)
                .allowsHitTesting(false)
            HStack(spacing: SeamlySpace.s3) {
                Image(systemName: "record.circle").font(.system(size: 20, weight: .light))
                Text(recording ? "录制中" : "录制").font(SeamlyFont.headline)
            }
            .foregroundStyle(SeamlyColor.inkInverse)
            .allowsHitTesting(false)
        }
        .frame(height: 52)
        .frame(maxWidth: .infinity)
    }
}
