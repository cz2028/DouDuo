import SwiftUI

/// 播放倍速档位与自定义解析（播放页菜单 / 视频设置面板共用）。
enum DYPlaybackRates {
    static let customKey = "douyin_custom_rate_v1"
    static let presets: [Double] = [0.1, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]
    static let minRate = 0.1
    static let maxRate = 4.0
    static func title(_ r: Double) -> String { r == 1 ? "1" : String(format: "%g", r) }
    static func isCustom(_ r: Double) -> Bool { !presets.contains(where: { abs($0 - r) < 0.001 }) }
    /// 解析用户输入，限幅到 0.1~4.0；无效输入返回 nil。
    static func parse(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "倍", with: "")
        guard let v = Double(t), v.isFinite else { return nil }
        return min(maxRate, max(minRate, v))
    }

    /// 菜单里只显示这一项：自定义填的值；没填或无效就是 1.0。
    static func menuValue(_ custom: String) -> Double { parse(custom) ?? 1.0 }
    static func menuTitle(_ custom: String) -> String { title(menuValue(custom)) }

    /// 播放页快捷按钮的循环顺序：常用档 + 用户自定义档（自定义值也参与循环）。
    static func cycle(_ custom: String) -> [Double] {
        var arr = [0.5, 1.0, 1.25, 1.5, 2.0, 3.0]
        if let r = parse(custom), !arr.contains(where: { abs($0 - r) < 0.001 }) { arr.append(r) }
        return arr.sorted()
    }

    /// 循环到下一档；当前值不在序列里时从第一档开始。
    static func next(_ current: Double, custom: String) -> Double {
        let arr = cycle(custom)
        guard let i = arr.firstIndex(where: { abs($0 - current) < 0.001 }) else { return arr.first ?? 1.0 }
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
    @AppStorage(DYPlaybackRates.customKey) private var customRateText = ""
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
                                    // 不列预设档：这一格显示的就是自定义填的值（空 = 1.0），
                                    // 想依次切档用播放页的快捷倍速按钮。
                                    let shown = DYPlaybackRates.menuValue(customRateText)
                                    rateChip(DYPlaybackRates.title(shown), selected: true) {
                                        customRateText = String(format: "%g", shown)
                                        showCustomRate = true
                                    }
                                    .accessibilityLabel("自定义倍速 \(shown)")
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
        .onAppear { playbackRate = DYPlaybackRates.menuValue(customRateText) }
        .alert("自定义倍速", isPresented: $showCustomRate) {
            TextField("0.1 ~ 4.0", text: $customRateText)
                .keyboardType(.decimalPad)
            Button("取消", role: .cancel) {}
            Button("确定") {
                // 空 / 无效输入一律回 1.0，并写回显示值，别留下脏字符串
                let r = DYPlaybackRates.parse(customRateText) ?? 1.0
                customRateText = String(format: "%g", r)
                playbackRate = r
            }
        } message: {
            Text("输入 0.1 到 4.0 之间的倍速，例如 0.3、1.8、3.0。")
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
