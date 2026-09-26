import CoreGraphics
import Foundation
import StitchKit

/// What a stored capture looks like to the interface.
///
/// Everything here is derived, never stored: `Placement` loads no images and a re-derive costs
/// a walk over the manifest, so there is nothing to invalidate and nothing to go stale after a
/// repair. `refinementDelta: 0` matches `StitchAssembler.composite` — the manifest is the
/// authority and the draw path never re-searches.
extension Capture {
    /// The finished composite in source pixels — the width of a keyframe by the placed height.
    var pixelSize: CGSize {
        CGSize(
            width: session.keyframes.first?.pixelWidth ?? 0,
            height: placement.totalHeight
        )
    }

    var findings: [Finding] {
        CaptureFindings.all(in: session, placement: placement)
    }

    /// How many findings each badge speaks for. On `Capture` rather than in a view, because
    /// three screens show these counts and "which kinds read as flagged" must be answered once —
    /// a capture that says "1 flagged" on Home and "2 flagged" in Library is the same state
    /// reading two ways, which is the thing the badges exist to prevent.
    var flaggedCount: Int { findings.filter { $0.kind == .seam || $0.kind == .bars }.count }
    var gapCount: Int { findings.filter { $0.kind == .gap }.count }

    var displayMarks: [CaptureMark] {
        CaptureMarks.all(in: session, placement: placement, findings: findings)
    }

    /// "今天" / "昨天" / "8月16日" — a capture is named by when it was made.
    ///
    /// The long form is left to the system locale rather than hard-coded: the two words that need
    /// saying are the relative ones, and a fixed `"8月16日"` pattern would be wrong in any
    /// language the app is eventually localized into.
    var title: String {
        let calendar = Calendar.current
        let date = session.createdAt
        if calendar.isDateInToday(date) { return "今天" }
        if calendar.isDateInYesterday(date) { return "昨天" }
        return date.formatted(.dateTime.day().month(.wide))
    }
}
