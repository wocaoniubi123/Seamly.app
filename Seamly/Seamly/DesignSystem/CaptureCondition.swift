import Foundation
import StitchKit

/// The facts a finished capture can exhibit, reduced to plain values.
///
/// Deliberately *not* built from `Capture`: keeping this a plain struct keeps the verdict
/// below a pure function — off the main actor, off disk, and table-testable across every
/// combination.
///
/// `nonisolated` because this app target defaults new declarations to `@MainActor`
/// (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`); without it this type — and everything
/// below that touches it — would only be usable from the main actor, defeating the point.
nonisolated struct CaptureFacts: Equatable {
    var segmentBreaks: Int = 0
    var flaggedSeams: Int = 0
    var unresolvedChrome: Int = 0
    var isIncomplete: Bool = false
    var orderAssumed: Bool = false
}

nonisolated extension CaptureFacts {
    /// Read the facts off a stored session. This is the only place that touches `StitchKit`.
    init(_ session: StitchSession) {
        self.init(
            segmentBreaks: session.segmentBreaks.count,
            flaggedSeams: session.seams.filter(\.isLowConfidence).count,
            unresolvedChrome: session.keyframes.filter {
                !session.chromeEdgesNeedingReview(for: $0).isEmpty
            }.count,
            isIncomplete: session.status == .recording,
            orderAssumed: session.orderAssumed
        )
    }
}

/// How loudly to present an observation. Two levels only — a longer scale invites the
/// badge-dumping the harness UI did.
nonisolated enum Severity {
    case guidance
    case warning
}

/// One plain-language observation about a capture.
nonisolated struct Imperfection: Equatable, Identifiable {
    /// Declaration order **is** the ranking, most important first. The user sees one line,
    /// so this decides which. Missing content outranks cosmetic misalignment; an ordering
    /// note is the quietest thing we can say.
    enum Kind: Int, Comparable, CaseIterable {
        case endedEarly
        case gaps
        case unresolvedBars
        case flaggedJoins
        case orderAssumed

        static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }
    }

    let kind: Kind
    let headline: String
    let detail: String
    let severity: Severity
    /// True when re-recording is the only available fix. False when the content is all
    /// present and merely imperfectly joined — guided repair (Spec 2) is the real answer
    /// there, and telling the user to record again would waste their time.
    let recommendsRecordingAgain: Bool
    /// True when the fix for this observation is lining the join up by hand, rather than recording
    /// again.
    ///
    /// Deliberately **not** the inverse of `recommendsRecordingAgain`: an assumed order is neither
    /// (dragging one join cannot reorder a capture), and "some bars may repeat" is both — no new
    /// recording helps, and lining up genuinely does, because the rows hidden behind an undetected
    /// bar come back once the two halves are continuous. The band itself stays; removing it is not
    /// this gesture's job, and cannot be folded into it (see the spec's "Out of scope").
    let canBeLinedUp: Bool

    var id: Kind { kind }
}

/// The single user-facing verdict on a capture. This type owns the *only* translation from
/// pipeline facts into language a user reads — "seam", "chrome", "segment", and "confidence"
/// never appear on the far side of it.
///
/// This type is the **aggregate** verdict — one line for the whole capture. `Finding` in
/// `CaptureFinding.swift` is the per-item companion the design's repair queue walks, and the
/// two split the vocabulary deliberately: this type's `Imperfection` wording predates the
/// design system and avoids pipeline words; `Finding`'s uses them, because the design puts
/// them on screen. Both live in this folder so there is still exactly one place where a
/// pipeline fact becomes English.
nonisolated enum CaptureCondition: Equatable {
    case stitching
    case clean
    case imperfect(primary: Imperfection, all: [Imperfection])
    case nothingToStitch
    case failed(String)

    /// The verdict for a capture that stitched successfully. The other cases are decided by
    /// the caller from the capture's phase and import outcome.
    init(ready facts: CaptureFacts) {
        let all = Imperfection.Kind.allCases.compactMap { Imperfection(kind: $0, facts: facts) }
        guard let primary = all.first else { self = .clean; return }
        self = .imperfect(primary: primary, all: all)
    }

    /// Whether the result screen should offer "Record again" as a prominent action.
    var recommendsRecordingAgain: Bool {
        switch self {
        case .imperfect(let primary, _): primary.recommendsRecordingAgain
        case .nothingToStitch, .failed: true
        case .clean, .stitching: false
        }
    }

    /// Whether the result screen should offer the repair at all.
    ///
    /// Read over **every** observation, unlike `recommendsRecordingAgain`, which reads only the
    /// primary: a capture can have ended early *and* have a join worth fixing, and "record again"
    /// being the loudest advice does not make the image already on disk unfixable.
    ///
    /// A clean capture offers it too — quietly. This app's own history is that a green verdict has
    /// been confidently wrong, so flagged-only entry would leave a visibly bad stitch with no
    /// recourse but re-recording. Whether there is actually a join to drag is a question about the
    /// session, not about this verdict, and belongs to `RepairableJoins`.
    var offersLiningUp: Bool {
        switch self {
        case .clean: true
        case .imperfect(_, let all): all.contains(where: \.canBeLinedUp)
        case .stitching, .nothingToStitch, .failed: false
        }
    }

    /// The repair screen opened on a capture with no join it can walk to at all. Structurally
    /// unreachable — `RepairableJoins.opening(in:flaggedOnly:)` gates whether the entry appears —
    /// but the screen still says something rather than sitting on a spinner forever.
    ///
    /// Here rather than in the view for the reason the whole type exists: "there is no walkable
    /// seam pair in this session" is a pipeline fact, and this is the only place one becomes
    /// English.
    static let nothingToLineUpMessage = "这里没有可以对齐的地方。"

    /// The manifest does not describe the join being opened — a keyframe missing either side of it,
    /// or no seam recorded for the pair (`JoinAlignment.init?` returning `nil`). Distinct from
    /// `nothingToLineUpMessage`: there *is* a join at this position, but what was saved about it is
    /// incomplete, so nothing can be placed on screen honestly.
    static let joinNotDescribedMessage = "这一段没有保存下来，所以没有东西可以对齐。"
}

nonisolated extension CaptureCondition {
    /// Turn a thrown error into something a person can read.
    ///
    /// The pipeline's error types are plain `Error` enums with no `LocalizedError`
    /// conformance, so `localizedDescription` bridges them to *"The operation couldn't be
    /// completed. (StitchKit.Compositor.CompositorError error 1.)"* — which is what a user saw
    /// on the screen a failed capture navigates to automatically. `StitchKit` is the finished
    /// core and stays untouched, so the translation lives here, alongside the only other place
    /// that turns pipeline facts into user-facing language.
    ///
    /// Callers still log the raw error to `Diagnostics`: this is what the user reads, not what
    /// we keep.
    static func message(for error: Error) -> String {
        switch error {
        case Compositor.CompositorError.noKeyframes, BatchStitcher.StitchError.empty:
            "没有保存下可供拼接的内容。"
        case Compositor.CompositorError.contextFailure:
            "内存不足，拼不出一张这么长的图。"
        case KeyframeIO.IOError.decodeFailed:
            "有一部分保存下来的画面读不回来了。"
        case KeyframeIO.IOError.encodeFailed:
            "这些画面没法保存到本机。"
        case KeyframeIO.IOError.sizeMismatch:
            "有一张保存的画面尺寸和录制时不一致。"
        case VideoKeyframeSource.VideoError.noVideoTrack:
            "这个文件里没有视频轨道。"
        case VideoKeyframeSource.VideoError.readFailed:
            "这个视频读不出来。"
        case MediaImporter.ImportError.notEnoughContent:
            "内容太少，没有可以拼到一起的部分。"
        case is KeyframeChromeValidationError:
            "这次录制保存的数据对不上，没法重建。"
        default:
            unrecognizedMessage(for: error)
        }
    }

    /// An error we have no wording for. Prefer whatever the error itself says — a Foundation or
    /// AVFoundation failure carries a perfectly good sentence — and substitute a generic line
    /// only when the description would be the system's placeholder, which names the failing
    /// Swift type and tells a user nothing.
    private static func unrecognizedMessage(for error: Error) -> String {
        if let described = (error as? LocalizedError)?.errorDescription, !described.isEmpty {
            return described
        }
        let bridged = error as NSError
        let described = bridged.localizedDescription
        // The placeholder interpolates the domain — which for a bridged Swift error is the
        // type's own name — so a description containing its own domain carries no real message.
        guard !described.isEmpty, !described.contains(bridged.domain) else {
            return "出了点问题，这一步没能完成。"
        }
        return described
    }
}

nonisolated private extension Imperfection {
    /// Build the observation for one kind, or `nil` if the facts do not exhibit it.
    init?(kind: Kind, facts: CaptureFacts) {
        switch kind {
        case .endedEarly:
            guard facts.isIncomplete else { return nil }
            self.init(
                kind: kind,
                headline: "录制提前结束了",
                detail: "这是停止之前保存下来的全部内容。",
                severity: .warning,
                recommendsRecordingAgain: true,
                canBeLinedUp: false
            )

        case .gaps:
            guard facts.segmentBreaks > 0 else { return nil }
            self.init(
                kind: kind,
                headline: "由 \(facts.segmentBreaks + 1) 段拼成",
                detail: "有几处滑得太快，没能接成连续的一张。",
                severity: .warning,
                recommendsRecordingAgain: true,
                canBeLinedUp: false
            )

        case .unresolvedBars:
            guard facts.unresolvedChrome > 0 else { return nil }
            self.init(
                kind: kind,
                headline: "顶栏/底栏可能重复",
                detail: "有 \(facts.unresolvedChrome) 屏分不清哪些是应用自己的栏。",
                severity: .guidance,
                recommendsRecordingAgain: false,
                canBeLinedUp: true
            )

        case .flaggedJoins:
            guard facts.flaggedSeams > 0 else { return nil }
            self.init(
                kind: kind,
                headline: "有一处拼接可能没对齐",
                detail: "有 \(facts.flaggedSeams) 处可能偏了一点。",
                severity: .guidance,
                recommendsRecordingAgain: false,
                canBeLinedUp: true
            )

        case .orderAssumed:
            guard facts.orderAssumed else { return nil }
            self.init(
                kind: kind,
                headline: "按拍摄顺序排列",
                detail: "没法靠画面内容判断先后，所以沿用了原来的顺序。",
                severity: .guidance,
                recommendsRecordingAgain: false,
                canBeLinedUp: false
            )
        }
    }

    /// 中文不需要单复数一致，`plural` 只为保持调用点签名不变而保留。
    static func count(_ n: Int, _ unit: String, _: String) -> String {
        "\(n)\(unit)"
    }
}
