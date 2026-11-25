import SwiftUI

/// 竖滑分页「提前挂载」窗口。
/// 以前分页器用 LazyVStack：下一条要等滑进屏幕才创建页面 → 建播放器、挂画面层、解第一帧都发生在滑动那一刻，
/// 期间只能先铺封面，看起来就是「每条先闪一下封面再播」，网络慢时还会卡住。
/// 现在当前条前 1 条、后 2 条始终挂着真页面（播放器暂停在第一帧、画面层已就绪），滑过去直接是真画面并立刻起播；
/// 窗口外只放轻量占位（黑底 + 近处的封面），页数再多也不建播放器。
enum DYPagerWindow {
    static let behind = 1
    /// 提前挂载几条 = 设置里的缓存条数（5 条就挂 5 页，上限 10），跟暖机数一致。
    /// 之前写死 1 页：老板设 10 条缓存也只挂下一条，而「未就绪就弹回」的规则又拦着，导致每次都要滑两次。
    static var ahead: Int { min(max(DYVideoCache.limit, 1), 10) }
    /// 占位里显示封面的范围（快速连滑越过挂载窗口时也不是纯黑）
    static let coverRange = 4

    static func mounts(_ index: Int, current: Int) -> Bool {
        index >= current - behind && index <= current + ahead
    }
    static func showsCover(_ index: Int, current: Int) -> Bool {
        abs(index - current) <= coverRange
    }
    static func currentIndex(_ items: [DYAweme], _ id: String?) -> Int {
        guard let id else { return 0 }
        return items.firstIndex { $0.id == id } ?? 0
    }
}

/// 窗口外的轻量占位：不建播放器、不挂手势。
struct DYPagerPlaceholder: View {
    let item: DYAweme
    let showsCover: Bool
    var body: some View {
        ZStack {
            Color.black
            if showsCover, let s = item.cover ?? item.images.first, let u = URL(string: s) {
                CachedAsyncImage(url: u) { img in img.resizable().scaledToFit() } placeholder: { Color.black }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 竖滑分页的页面列表（三个分页器共用）：当前页立即挂载；挂载窗口的整体平移推迟到滑动收尾、起播之后
/// （新挂一页 = 建播放器 + 解首帧，卸一页 = 销毁播放器，都在主线程，和起播挤在同一帧就会「卡一下」）。
///
/// 性能要点：窗口外的页只放轻量占位（黑底 + 近处封面），不建播放器 / KVO / 通知观察者。
/// 之前 ForEach(items) 无条件给每一页都挂真页面，刷得越多同时存活的 AVPlayer 越多，
/// 撞上系统硬解码会话上限后就越滑越卡。挂载窗口现在真正生效了。
struct DYPagerStack<Page: View>: View {
    let items: [DYAweme]
    let currentID: String?
    @ViewBuilder let page: (DYAweme) -> Page
    var pageAxes: Axis.Set = [.horizontal, .vertical]
    /// 已挂载窗口的中心。currentID 变化（起播）后平移：新窗口立即生效（保证要起播的页有真播放器），
    /// 旧窗口延迟 shiftDelay 再拆，避免「建播放器 + 销毁播放器」和起播挤在同一帧。
    @State private var centerID: String?
    @State private var previousCenterID: String?
    /// 拆旧页延后到动画结束之后（扩窗是即时的）
    static var shiftDelay: TimeInterval { 0.45 }

    private var centerIndex: Int { DYPagerWindow.currentIndex(items, centerID) }
    private var previousIndex: Int? { previousCenterID.map { DYPagerWindow.currentIndex(items, $0) } }

    private func isMounted(_ index: Int) -> Bool {
        if DYPagerWindow.mounts(index, current: centerIndex) { return true }
        if let p = previousIndex, DYPagerWindow.mounts(index, current: p) { return true }
        return false
    }

    var body: some View {
        // 惰性分页：每帧只重建可见的 1–2 页（之前非惰性版本每帧把已挂载页全部重建，实测主线程一帧掉到 35–45ms）
        LazyVStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Group {
                    if isMounted(index) {
                        page(item)
                            .containerRelativeFrame(pageAxes)
                            .id(item.id)
                    } else {
                        DYPagerPlaceholder(item: item, showsCover: DYPagerWindow.showsCover(index, current: centerIndex))
                            .containerRelativeFrame(pageAxes)
                            .id(item.id)
                    }
                }
            }
        }
        .onAppear { centerID = currentID ?? items.first?.id }
        .task(id: currentID) {
            guard let new = currentID, new != centerID else { return }
            previousCenterID = centerID
            centerID = new
            try? await Task.sleep(for: .seconds(Self.shiftDelay))
            guard !Task.isCancelled else { return }
            previousCenterID = nil
        }
    }
}
