import SwiftUI
import PhotosUI
import StitchKit

/// Where the app goes. Home is the root, because the app opens on the most recent capture.
enum Route: Hashable {
    case library
    case review(UUID)
}

/// `sheet(item:)` needs an `Identifiable`, and a bare `UUID` is not one.
private struct IdentifiedUUID: Identifiable { let id: UUID }

/// The one place the model is owned, the navigation stack lives, and every model-driven
/// presentation is decided. Screens take closures and know nothing about routing.
struct AppShell: View {
    @State private var model = CaptureModel()
    /// Whether the dock may offer Record at all on this device. Lives here, not in the dock,
    /// because `RPScreenRecorder.delegate` is weak and the observer must outlive every screen.
    @State private var liveCapture = LiveCaptureMonitor()
    /// The dock's two pickers write here, and the import runs off these. Owned by the shell
    /// because the same selection serves Home and Library.
    @State private var importFlow = ImportFlow()
    @State private var videoSelection: PhotosPickerItem?
    @State private var photoSelection: [PhotosPickerItem] = []
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    @State private var path: [Route] = []
    @State private var showFirstRun = false
    @State private var showDiagnostics = false
    @State private var showNothingToStitch = false

    /// A join to open the repair on. A wrapper rather than a bare `Int` so
    /// `fullScreenCover(item:)` can identify it.
    struct RepairTarget: Identifiable, Hashable {
        let captureID: UUID
        let findingNumber: Int
        var id: String { "\(captureID)-\(findingNumber)" }
    }

    @State private var repairTarget: RepairTarget?
    @State private var exportTarget: UUID?

    var body: some View {
        NavigationStack(path: $path) {
            HomeScreen(
                model: model,
                liveCapture: liveCapture.availability,
                onLibrary: { path.append(.library) },
                onReview: { path.append(.review($0)) },
                onRepair: { repairTarget = RepairTarget(captureID: $0, findingNumber: $1) },
                onHelp: { showFirstRun = true },
                videoSelection: $videoSelection,
                photoSelection: $photoSelection
            )
            .overlay { importOverlay }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                destination(route).toolbar(.hidden, for: .navigationBar)
            }
        }
        .task {
            if !hasSeenOnboarding { showFirstRun = true; hasSeenOnboarding = true }
            AppGroup.startBroadcastFinishObserver()
            await model.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .seamlyBroadcastFinished)) { _ in
            Task { await model.refresh() }
        }
        // MARK: - The two import paths, opened straight from the dock's buttons
        //
        // `PhotosPicker` opens the library by making its label the button, so there is no sheet
        // to present and no second tap: the pick lands here and the work starts.
        .onChange(of: videoSelection) { _, item in
            guard let item else { return }
            // Cleared up front: `PhotosPickerItem` is `Equatable` and `.onChange` only fires on a
            // *change*, so a selection left standing would make re-picking the same recording a
            // no-op and the dock button would read as dead.
            videoSelection = nil
            Task { await importFlow.loadVideo(item, into: model) }
        }
        .onChange(of: photoSelection) { _, items in
            guard !items.isEmpty else { return }
            photoSelection = []
            Task { await importFlow.loadPhotos(items, into: model) }
        }
        // The overlay's lifetime is the union of two phases, and both are needed:
        //
        //  1. `importFlow.running` — the pick has landed and the flow is decoding it. There is
        //     no progress value here, because the work is data-dependent.
        //  2. The model's own flags — after the flow hands the images over, STITCHING is still
        //     running inside `CaptureModel`, and dropping the overlay when `loadPhotos` returned
        //     would leave the dock live over work that has not started yet.
        //
        // No deadline task watches this. A timer would have to guess how long the handoff takes,
        // and guessing wrong either hides the overlay mid-decode or leaves it over a finished
        // import — the two failures the flag pair already rules out.
        .onChange(of: model.pendingResult) { _, id in
            guard id != nil else { return }
            importFlow.finish()
            path.removeAll()
            model.consumePendingResult()
        }
        // React to the flag being *set*, not to it changing: `lastPickupWasEmpty` is an event,
        // and consuming it immediately is what lets a second consecutive empty pickup set it
        // `true` again and fire this a second time.
        .onChange(of: model.lastPickupWasEmpty) { _, empty in
            guard empty else { return }
            // The overlay comes down first. `notEnoughContent` raises THIS flag rather than
            // `importError`, so an overlay left standing would sit on top of the explanation
            // that says what happened — over an import that produced nothing.
            importFlow.finish()
            showNothingToStitch = true
            model.consumeLastPickupWasEmpty()
        }
        .sheet(isPresented: $showFirstRun) {
            FirstRunView(onDone: { showFirstRun = false })
                .interactiveDismissDisabled(false)
        }
        .sheet(isPresented: $showDiagnostics) { DiagnosticsView() }
        // An import that failed before the model was involved — a pick that would not decode, or
        // fewer than two screenshots — has no capture to fail OVER, so it is stated plainly and
        // dismissed. A model-side failure lands on the capture's own `.failed` screen instead,
        // which is why this reads `importError` and not `phase`.
        .alert(
            "导入失败",
            isPresented: Binding(
                get: { model.importError != nil },
                set: { if !$0 { model.clearImportError() } }
            )
        ) {
            Button("好", role: .cancel) { model.clearImportError() }
        } message: {
            Text(model.importError ?? "")
        }
        .sheet(isPresented: $showNothingToStitch) {
            nothingToStitch.presentationDetents([.medium])
        }
        .fullScreenCover(item: $repairTarget) { target in
            RepairQueueView(
                captureID: target.captureID,
                model: model,
                startAt: target.findingNumber,
                onClose: { repairTarget = nil }
            )
        }
        .sheet(item: Binding(
            get: { exportTarget.map { IdentifiedUUID(id: $0) } },
            set: { exportTarget = $0?.id }
        )) { target in
            ExportSheet(captureID: target.id, model: model, onClose: { exportTarget = nil })
                .presentationDetents([.medium, .large])
        }
    }

    /// The import, where it happens: over the capture area, in place. Never a sheet — the sheet
    /// was the thing being removed.
    ///
    /// `importProgress` is a real percentage only while decoding a recording; stitching has none,
    /// and passing `nil` is what makes `ProgressNote` sweep instead of claim a fraction.
    private var importing: Bool {
        importFlow.running || model.isAssemblingNewArrival || model.importProgress != nil
    }

    @ViewBuilder
    private var importOverlay: some View {
        if importing {
            VStack(spacing: SeamlySpace.s5) {
                ProgressNote(
                    label: model.importProgress != nil ? "正在读取录屏…" : "正在拼接…",
                    value: model.importProgress
                )
                Text(model.importProgress != nil
                     ? "正在把录屏解码成关键帧，只保留画面有变化的帧。"
                     : "正在把每一帧和上一帧对齐。这一步没有百分比——找到接缝就算完成。")
                    .font(SeamlyFont.footnote)
                    .foregroundStyle(SeamlyColor.inkMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: SeamlySpace.columnMax)
            }
            .padding(SeamlySpace.s5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SeamlyColor.paper.opacity(0.94))
            .accessibilityIdentifier("import-progress")
        }
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .library:
            LibraryScreen(
                model: model,
                liveCapture: liveCapture.availability,
                onOpen: { path.append(.review($0)) },
                onBack: { path.removeLast() },
                videoSelection: $videoSelection,
                photoSelection: $photoSelection,
                onDiagnostics: { showDiagnostics = true }
            )        case .review(let id):
            ReviewScreen(
                captureID: id,
                model: model,
                onBack: { path.removeLast() },
                onRepair: { repairTarget = RepairTarget(captureID: id, findingNumber: $0) },
                onExport: { exportTarget = id }
            )
        }
    }

    @ViewBuilder
    private var nothingToStitch: some View {
        EmptyState(
            symbol: "arrow.up.and.down",
            title: "没有可拼的内容",
            message: "这段录屏里没有滑动，所以没有可以拼起来的画面。开始录制后切到你要截的应用，再匀速往下滑。"
        ) {
            SeamlyButton("重新录制") { showNothingToStitch = false }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SeamlyColor.paper)
    }
}
