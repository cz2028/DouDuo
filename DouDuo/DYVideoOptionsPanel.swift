import SwiftUI

/// 播放倍速档位与自定义解析（播放页菜单 / 视频设置面板共用）。
enum DYPlaybackRates {
    static let customKey = "douyin_custom_rate_v1"
    static let minRate = 0.1
    static let maxRate = 4.0
    static let `default` = 1.0

    static func title(_ r: Double) -> String { r == 1 ? "1" : String(format: "%g", r) }

    /// 把单个 token 解析成倍速；兼容中文输入法小数点。无效返回 nil。
    static func parse(_ s: String) -> Double? {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "倍", with: "")
        for mark in ["。", "．"] { t = t.replacingOccurrences(of: mark, with: ".") }
        guard let v = Double(t), v.isFinite else { return nil }
        return min(maxRate, max(minRate, v))
    }

    /// 解析用户输入的整串倍速列表：统一用减号 - 分隔（中英文键盘同一个键，不用区分标点）。
    /// 去重、限幅、过滤非法值；空或全非法时保底 [1]，保证按钮至少有一档可切。
    static func parseList(_ s: String) -> [Double] {
        // 全角／长减号也当分隔符，中英文打出来的横杠都能用
        let normalized = s.replacingOccurrences(of: "－", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
        var out: [Double] = []
        for token in normalized.split(separator: "-") {
            guard let v = parse(String(token)) else { continue }
            if !out.contains(where: { abs($0 - v) < 0.001 }) { out.append(v) }
        }
        return out.isEmpty ? [`default`] : out
    }

    /// 输入框文字的规范写法：减号分隔，用于保存时回写。
    static func serialize(_ list: [Double]) -> String {
        (list.isEmpty ? [`default`] : list).map(title).joined(separator: "-")
    }

    /// 快捷按钮的循环档位：完全来自输入框，没有任何硬编码预设。
    static func cycle(_ custom: String) -> [Double] { parseList(custom) }

    /// 循环到下一档；当前值不在列表里时从第一档开始。
    static func next(_ current: Double, custom: String) -> Double {
        let arr = cycle(custom)
        guard let i = arr.firstIndex(where: { abs($0 - current) < 0.001 }) else { return arr[0] }
        return arr[(i + 1) % arr.count]
    }
}

/// Shared by recommendation, following and every works player. These are the
/// existing persisted preferences; moving their controls does not reset them.
@available(iOS 27.1, *)
struct DYVideoOptionsPanel: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @AppStorage("douyin_muted_v1") private var muted = false
    @AppStorage(DYVideoFit.preferenceKey) private var autoFit = true
    @AppStorage("douyin_playback_rate_v1") private var playbackRate = 1.0
    @AppStorage("douyin_bg_play_v1") private var backgroundPlay = false
    @AppStorage("douyin_autoplay_v1") private var autoNext = false
    @State private var listAtTop = true
    @State private var headerHeight: CGFloat = 44
    @State private var showCustomRate = false
    @AppStorage(DYPlaybackRates.customKey) private var customRateText = "1"
    /// 弹窗输入框临时值：不直接绑 @AppStorage，避免点确定时最后输入没同步回去被抹掉
    @State private var rateInputText = "1"
    var onDislike: (() -> Void)?
    var onSendDanmaku: (() -> Void)?
    var onWatchLater: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("视频设置").font(.subheadline.weight(.semibold))
                HStack {
                    Spacer()
                    Button("关闭设置", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly).frame(width: 44, height: 44).contentShape(Rectangle())
                        .accessibilityIdentifier("douyin.options.close")
                }
            }
            .padding(.horizontal, 12)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
            .contentShape(Rectangle())
            .modifier(DYPanelDismissGesture(onClose: { dismiss() }))
            ScrollView {
                VStack(spacing: 12) {
                    HStack(spacing: 0) {
                        if DYVideoFit.showsLabeledControl(on: .classicOptions) {
                            shortcut(DYVideoFit.title, icon: "arrow.up.left.and.arrow.down.right",
                                     selected: autoFit, id: "douyin.options.fit") { autoFit.toggle() }
                        }
                        shortcut("静音", icon: muted ? "speaker.slash" : "speaker.wave.2",
                                 selected: muted, id: "douyin.options.muted") { muted.toggle() }
                        shortcut("听书模式", icon: "headphones",
                                 selected: backgroundPlay, id: "douyin.options.bgplay") { backgroundPlay.toggle() }
                        shortcut("自动连播", icon: "play.square.stack",
                                 selected: autoNext, id: "douyin.options.autonext") { autoNext.toggle() }
                        if let onDislike {
                            shortcut("不感兴趣", icon: "hand.thumbsdown", selected: false,
                                     id: "douyin.dislike") {
                                dismiss()
                                onDislike()
                            }
                        }
                    }
                    .padding(.vertical, 12)

                    VStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("倍速", systemImage: "speedometer")
                                .font(.subheadline.weight(.semibold))
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    // 显示当前实际生效的倍速；点开编辑整串倍速列表。
                                    rateChip(DYPlaybackRates.title(playbackRate), selected: true) {
                                        rateInputText = customRateText
                                        showCustomRate = true
                                    }
                                    .accessibilityLabel("当前倍速 \(playbackRate)")
                                    .accessibilityIdentifier("douyin.options.rate.custom")
                                }
                            }
                        }
                        .padding(16)
                        if let onSendDanmaku {
                            Divider().padding(.leading, 16)
                            Button("发弹幕", systemImage: "text.bubble") {
                                dismiss()
                                onSendDanmaku()
                            }
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                            .accessibilityIdentifier("douyin.danmaku.open")
                        }
                        if let onWatchLater {
                            Divider().padding(.leading, 16)
                            Button("稍后再看", systemImage: "clock") {
                                dismiss()
                                onWatchLater()
                            }
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                            .accessibilityIdentifier("douyin.watchlater.add")
                        }
                    }
                    .optionGroup()
                }
                .padding(.horizontal, 16).padding(.top, 4)
                .padding(.bottom, max(16, DYDuoMetrics.windowBottomInset + 4))
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: DYBottomPanelContentHeightKey.self,
                                               value: headerHeight + geometry.size.height)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top <= 1 } action: { _, atTop in listAtTop = atTop }
            .modifier(DYPanelDismissGesture(isAtTop: listAtTop, onClose: { dismiss() }))
            .accessibilityIdentifier("douyin.options.list")
        }
        .font(.subheadline)
        .foregroundStyle(.primary)
        .tint(theme.accent.color(for: scheme))
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("douyin.options.panel")
        .onAppear {
            // 用户改过列表后，当前倍速可能已不在列表里，纠正到第一档
            if !DYPlaybackRates.cycle(customRateText).contains(where: { abs($0 - playbackRate) < 0.001 }) {
                playbackRate = DYPlaybackRates.cycle(customRateText)[0]
            }
        }
        .alert("自定义倍速", isPresented: $showCustomRate) {
            TextField("1-1.5-2", text: $rateInputText)
            Button("取消", role: .cancel) {}
            Button("确定") {
                let list = DYPlaybackRates.parseList(rateInputText)
                let saved = DYPlaybackRates.serialize(list)
                customRateText = saved
                rateInputText = saved
                // 立即落盘，不依赖 @AppStorage 的延迟同步
                UserDefaults.standard.set(saved, forKey: DYPlaybackRates.customKey)
                if !list.contains(where: { abs($0 - playbackRate) < 0.001 }) { playbackRate = list[0] }
            }
        } message: {
            Text("多个倍速用减号 - 隔开（0.1~4.0），例如 1-1.5-2。倍速按钮只在这些值之间切换；留空会保留 1。")
        }
    }

    /// 单独抽出，避免 SwiftUI 在 ForEach 内对复合 modifier 链做超长类型推断。
    private func rateChip(_ title: String, selected: Bool,
                          action: @escaping () -> Void) -> some View {
        let opacity: Double = selected ? 0.30 : 0.12
        return Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(selected ? .semibold : .regular)
                .foregroundStyle(.primary)
                .frame(width: 52, height: 44)
                .background(Capsule().fill(Color.black.opacity(opacity)))
                .contentShape(Rectangle())
        }
    }

    private func shortcut(_ title: String, icon: String, selected: Bool,
                          id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.title3)
                Text(title).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(.black.opacity(selected ? 0.30 : 0.12), in: RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 3)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier(id)
        .accessibilityValue(selected ? "开启" : "关闭")
    }

}

private extension View {
    func optionGroup() -> some View {
        background(.black.opacity(0.10), in: RoundedRectangle(cornerRadius: 24))
    }
}
