import SwiftUI
import StitchKit

/// A read-only view onto the shared diagnostics log (extension + app), with one-tap Share/Copy so
/// a capture that misbehaves can be reported without a Mac attached. Reads the App Group log that
/// both `SampleHandler` (category `capture`) and `CaptureModel` (category `app`) write to.
struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = "（加载中…）"
    @State private var clearError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("诊断日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: text) { Image(systemName: "square.and.arrow.up") }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("拷贝", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
                    Spacer()
                    Button("刷新", systemImage: "arrow.clockwise") { load() }
                    Spacer()
                    Button("清空", systemImage: "trash", role: .destructive) { clear() }
                }
            }
            .task { load() }
            .alert("没能清空日志", isPresented: .constant(clearError != nil)) {
                Button("好") { clearError = nil }
            } message: {
                Text(clearError ?? "")
            }
        }
    }

    private func load() {
        guard let container = AppGroup.containerURL else {
            text = "这个版本拿不到 App Group，读不了诊断日志。"
            return
        }
        text = Diagnostics.readAll(containerURL: container)
    }

    private func clear() {
        guard let container = AppGroup.containerURL else { return }
        do {
            try Diagnostics.clear(containerURL: container)
            load()
        } catch {
            clearError = error.localizedDescription
        }
    }
}
