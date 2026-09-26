import SwiftUI
import PhotosUI

/// Every capture. Compact is a ruled list; regular is a grid of uniform 3:5 cells. The dock
/// stays, because the capture affordance is permanently present.
struct LibraryScreen: View {
    let model: CaptureModel
    var liveCapture: LiveCaptureAvailability = .available
    var onOpen: (UUID) -> Void
    var onBack: () -> Void
    /// Same two pickers as Home's dock, and the same shell-owned state behind them.
    @Binding var videoSelection: PhotosPickerItem?
    @Binding var photoSelection: [PhotosPickerItem]
    var onDiagnostics: () -> Void

    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass) private var vSize

    private var layout: SeamlyLayout { SeamlyLayout(horizontal: hSize, vertical: vSize) }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(
                title: "图库",
                subtitle: SeamlyNumber.counted(model.captures.count, "张截图", "张截图"),
                large: true,
                onBack: onBack
            ) {
                // Diagnostics is a developer surface, not a feature. It stays reachable
                // because the extension cannot draw UI and its container is not reliably
                // pullable over USB, so this log is the only window into a failed capture on a
                // device — but it lives behind an overflow, on the screen that already holds
                // everything else.
                Menu {
                    Button("诊断日志", systemImage: "stethoscope", action: onDiagnostics)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(SeamlyColor.inkMuted)
                        .seamlyHitTarget()
                }
                .accessibilityLabel("更多")
            }

            if model.captures.isEmpty {
                EmptyState(
                    symbol: "tray",
                    title: "还没有截图",
                    message: "你录制或导入的内容都会出现在这里。"
                )
                .frame(maxHeight: .infinity)
            } else if layout.isRegular {
                grid
            } else {
                list
            }

            CaptureDock(
                liveCapture: liveCapture,
                videoSelection: $videoSelection,
                photoSelection: $photoSelection
            )
            .padding(.horizontal, layout.gutter)
            .padding(.top, SeamlySpace.s5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SeamlyColor.paper)
    }

    private var list: some View {
        List {
            ForEach(model.captures) { capture in
                CaptureListRow(
                    capture: capture,
                    onOpen: { onOpen(capture.id) },
                    onDelete: { model.delete(capture.id) }
                )
                .listRowInsets(EdgeInsets(top: 0, leading: layout.gutter, bottom: 0, trailing: layout.gutter))
                .listRowSeparator(.hidden)
                .listRowBackground(SeamlyColor.paper)
            }
            // The two import rows used to be repeated here. They are gone because the dock
            // BELOW already carries both — and now each one opens its picker directly, so the
            // list was offering the same two taps twice on one screen.
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(SeamlyColor.paper)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 190), spacing: SeamlySpace.s7)],
                spacing: SeamlySpace.s7
            ) {
                ForEach(model.captures) { capture in
                    CaptureGridCard(
                        capture: capture,
                        onOpen: { onOpen(capture.id) },
                        onDelete: { model.delete(capture.id) }
                    )
                }
            }
            .padding(.horizontal, layout.gutter)
            .padding(.top, SeamlySpace.s5)
            .padding(.bottom, SeamlySpace.s8)
        }
    }
}
