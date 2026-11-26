import Foundation

/// 播放清晰度上限（长边像素）。
///
/// 抖音客户端默认不是原画：它按机型/网络选一个码率上限，再在范围内自适应。
/// 这个项目之前一直挑「有效码率最高」的一档，1080p / 2K 的 H.265 很常见：
/// 解码器参考帧缓冲更大，截屏、切后台、上滑回看时系统要合成的图层更贵，
/// 表现就是「系统级卡顿 + 内存高」，而不是播放卡。
///
/// 所以这里给出一个可调的上限，默认 720p：绝大多数竖屏视频肉眼无差，
/// 解码和合成开销约为 1080p 的 40%。
enum DYPlaybackQuality: Int, CaseIterable, Identifiable {
    case p540 = 540
    case p720 = 720
    case p1080 = 1080
    /// 0 表示不设上限，跟着抖音给的最高档走
    case original = 0

    static let storageKey = "dd_play_max_res_v1"
    static let webStorageKey = "dd_max_res"

    var id: Int { rawValue }

    /// 长边上限，0 = 不限
    var maxEdge: Int { rawValue }

    var title: String {
        switch self {
        case .p540: "540p（最省）"
        case .p720: "720p（推荐）"
        case .p1080: "1080p"
        case .original: "原画"
        }
    }

    var detail: String {
        switch self {
        case .p540: "解码压力最小，发热和卡顿最轻，画面略糊。"
        case .p720: "和抖音客户端默认差不多，肉眼几乎看不出差别，卡顿明显减少。"
        case .p1080: "清晰一些，1080p 视频占用的解码内存约为 720p 的两倍。"
        case .original: "抖音给什么就放什么，可能是 2K/4K，最吃内存、最容易卡。"
        }
    }

    static var current: DYPlaybackQuality {
        // 注意：不能用 integer(forKey:)——没存过时会返回 0，那是「原画」
        guard let raw = UserDefaults.standard.object(forKey: storageKey) as? Int,
              let q = DYPlaybackQuality(rawValue: raw) else { return .p720 }
        return q
    }

    static func store(_ q: DYPlaybackQuality) {
        UserDefaults.standard.set(q.rawValue, forKey: storageKey)
    }

    /// 注入签名页用的 JS：值放 localStorage（页面重载后仍生效），
    /// 没有记录时退回 UserDefaults 里的设置，而不是硬编码。
    static var injectionJS: String {
        let fallback = current.maxEdge
        return """
        (() => { try {
          const s = localStorage.getItem('\(webStorageKey)');
          window.__ddMaxRes = (s === null || s === '') ? \(fallback) : Number(s);
          if (!Number.isFinite(window.__ddMaxRes)) window.__ddMaxRes = \(fallback);
        } catch (e) { window.__ddMaxRes = \(fallback); } })();
        """
    }
}
