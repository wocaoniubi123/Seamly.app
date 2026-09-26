import SwiftUI
import PhotosUI
import CoreGraphics
import ImageIO

/// The import path, driven straight from the dock's two side buttons — **one tap, then the
/// system picker**.
///
/// This replaces the two-step route: tap *From a screen recording*, land in a sheet whose only
/// content was another tappable row, then tap that to get the picker. Two taps and a modal for
/// one decision — and the sheet said nothing the dock button had not already said.
///
/// `PhotosPicker` opens the library by building its *label* as the button, so the picker has to
/// live inside the dock button itself (`ImportTrigger`). What used to be `ImportSheet`'s state
/// splits accordingly:
///
/// - **Picking** is the picker's own modal and needs no state here.
/// - **Loading** is one flag, held until the model reports the import is over — the overlay's
///   lifetime.
/// - **Progress and failure** already live on `CaptureModel` (`importProgress`, `importError`),
///   which is why this type does not mirror them.
///
/// `nonisolated` because `PhotosPicker`'s `label:` closure is not MainActor-isolated; the app
/// target defaults declarations to `@MainActor`, and calling a main-actor-isolated helper from
/// inside that closure fails Sendability under Swift 6.
nonisolated final class ImportFlow: ObservableObject {
    enum Source { case video, photos }

    /// Set when a pick lands, cleared when the model stops assembling. Owns the overlay.
    @Published private(set) var running = false

    func begin() { running = true }

    /// The model finished — or the shell says the work is over.
    func finish() { running = false }

    func noteFailure(_ message: String, into model: CaptureModel) {
        model.setImportError(message)
        running = false
    }

    /// Decode one picked recording and hand it to the model.
    ///
    /// The caller clears its `PhotosPickerItem` binding up front, not on the success branch:
    /// `PhotosPickerItem` is `Equatable` and `.onChange` only fires on a *change*, so a selection
    /// still standing on return would make re-picking the same recording a no-op and the button
    /// would read as dead.
    @MainActor
    func loadVideo(_ item: PhotosPickerItem, into model: CaptureModel) async {
        begin()
        do {
            guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                noteFailure("这个视频读不出来。", into: model)
                return
            }
            await model.importVideo(movie.url)
        } catch {
            noteFailure(CaptureCondition.message(for: error), into: model)
        }
        finish()
    }

    /// Decode picked screenshots in pick order and hand them to the model.
    ///
    /// Every failure names WHICH item failed. "第 3 张读不出来" is the difference between "pick
    /// them again" and "one of your twenty taps was a video by mistake", and the position is the
    /// only part that can be acted on.
    @MainActor
    func loadPhotos(_ items: [PhotosPickerItem], into model: CaptureModel) async {
        begin()
        var images: [CGImage] = []
        for (i, item) in items.enumerated() {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    noteFailure("第 \(i + 1) 张读不出来。", into: model)
                    return
                }
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    noteFailure("第 \(i + 1) 张不是能解码的图片。", into: model)
                    return
                }
                images.append(image)
            } catch {
                noteFailure(CaptureCondition.message(for: error), into: model)
                return
            }
        }
        guard images.count >= 2 else {
            // Reading a photo LIBRARY item has no "too few" case — this is the model's own
            // `notEnoughContent` floor, stated before the work starts so the user is not told
            // "there wasn't enough here to join together" a minute later.
            noteFailure("至少要选两张有重叠的截图。", into: model)
            return
        }
        await model.importPhotos(images)
        finish()
    }
}

/// A dock button that IS the picker. Tapping it opens the photo library directly.
///
/// The label is drawn here rather than handing the picker a styled `Text`, because the dock's
/// buttons are 52 pt squares with a rule border and `PhotosPicker`'s own button chrome would
/// paint a background inside them.
struct ImportTrigger: View {
    let source: ImportFlow.Source
    @Binding var videoSelection: PhotosPickerItem?
    @Binding var photoSelection: [PhotosPickerItem]
    let symbol: String
    let label: String

    var body: some View {
        Group {
            if source == .video {
                PhotosPicker(selection: $videoSelection, matching: .videos) { sideLabel }
            } else {
                PhotosPicker(selection: $photoSelection, maxSelectionCount: 20, matching: .images) { sideLabel }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Mirrors `CaptureDock.side(symbol:label:action:)` exactly — same 52 pt square, same rule,
    /// same radius — so a dock button that opens a picker is indistinguishable from one that
    /// runs an action.
    private var sideLabel: some View {
        Image(systemName: symbol)
            .font(.system(size: 20))
            .foregroundStyle(SeamlyColor.ink)
            .frame(width: 52, height: 52)
            .background(SeamlyColor.paperRaised)
            .overlay {
                RoundedRectangle(cornerRadius: SeamlyRadius.sm, style: .continuous)
                    .strokeBorder(SeamlyColor.rule, lineWidth: 1)
            }
            .seamlyCorners(SeamlyRadius.sm)
            .contentShape(Rectangle())
    }
}
