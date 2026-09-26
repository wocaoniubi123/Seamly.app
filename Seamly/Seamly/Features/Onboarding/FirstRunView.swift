import SwiftUI

/// The only place the buzz can be taught. Nothing may be drawn during a broadcast, so its
/// meaning has to land before the session starts.
struct FirstRunView: View {
    let onDone: () -> Void

    @State private var page = 0

    private struct Step {
        let symbol: String
        let title: String
        let message: String
    }

    private let steps = [
        Step(symbol: "record.circle",
             title: "点录制，选 Seamly",
             message: "你在别的应用里滑动时，Seamly 会录制屏幕。在弹窗里选 Seamly，然后等倒计时结束。"),
        Step(symbol: "hand.draw",
             title: "震一下就是滑太快了",
             message: "切到你要截的应用，匀速往下滑。如果感觉震了一下，说明你滑得比帧率还快——放慢一点，或者往回滑一点。"),
        Step(symbol: "checkmark.seal",
             title: "停止录制，回到 Seamly",
             message: "点红色指示条停止录制，然后回到 Seamly。长图已经拼好在那里，有不确定的地方都标出来了。"),
    ]

    private var isLast: Bool { page == steps.count - 1 }

    var body: some View {
        VStack(spacing: SeamlySpace.s7) {
            // The card scrolls; the dots and the button do not. At
            // `accessibility-extra-extra-extra-large` step 2's card is taller than the screen,
            // and without this it pushed "Next" clean off the bottom — 1 061 pt down an 874 pt
            // screen, past even VoiceOver's scroll-to-visible. First run became a dead end at
            // the largest text size, which is precisely the user who most needs the explanation.
            //
            // `minHeight: proxy.size.height` with `.center` keeps the card vertically centred
            // whenever it *does* fit, so the ordinary case looks exactly as it did.
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: SeamlySpace.s7) {
                        CueCard(
                            symbol: steps[page].symbol,
                            title: steps[page].title,
                            message: steps[page].message
                        )
                        if page == 1 {
                            Text("录制期间 Seamly 没法在屏幕上显示任何东西——任何横幅都会被一起录进去。震动是它唯一能给你的提示。")
                                .font(SeamlyFont.footnote)
                                .foregroundStyle(SeamlyColor.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: SeamlySpace.columnMax)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            PageDots(count: steps.count, index: page)

            SeamlyButton(isLast ? "开始使用" : "下一步", size: .large) {
                if isLast { onDone() } else { withAnimation(SeamlyMotion.base) { page += 1 } }
            }
            .frame(maxWidth: SeamlySpace.columnMax)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, SeamlySpace.gutterCompact)
        .padding(.vertical, SeamlySpace.s7)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SeamlyColor.paper)
    }
}
