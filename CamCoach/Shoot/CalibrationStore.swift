// SPDX-License-Identifier: Apache-2.0
import Foundation

/// 一条标定样本：当时的画面统计 + 相机参数 + 一句人给的判断。
///
/// 为什么只存数字不存图：要把 2% / 0.6% / 35% 这几个阈值换成实测值，
/// 需要的只是「这一帧亮部占了多少、你觉得算不算废」。
/// 存图再想办法传回来，成本远高于把几个百分比复制成一段文字。
struct SampleRecord: Codable, Identifiable {

    var id = UUID()
    var at: Date
    /// 亮部（≥250）像素占比，0...1。
    var highlight: Double
    /// 暗部（≤8）像素占比，0...1。
    var shadow: Double
    /// 平均亮度，0...1。
    var mean: Double
    var shutter: String
    var aperture: String
    var iso: String
    var focalMM: Int
    /// 人给的判断：能看 / 糊了 / 过曝 / 欠曝。
    var verdict: String
}

/// 跨页面共用的小设置。
///
/// 焦距只存在本机：相机没通过 PTP 报这一项，而安全快门必须知道它。
/// 用户选一次就记住，取景页和标定页读的是同一个 key。
enum CameraSettings {
    static let focalKey = "camcoach.focal"
    static let focalChoices = [24, 35, 50, 85, 105, 135]
    static let defaultFocal = 50
}

/// 标定样本的存储。存 UserDefaults，重启不丢。
final class CalibrationStore: ObservableObject {

    static let shared = CalibrationStore()

    @Published private(set) var records: [SampleRecord] = []

    private let key = "camcoach.calibration.samples"

    private init() {
        load()
    }

    func add(_ r: SampleRecord) {
        records.append(r)
        save()
    }

    func remove(id: UUID) {
        records.removeAll { $0.id == id }
        save()
    }

    func clear() {
        records.removeAll()
        save()
    }

    /// 复制成 TSV 用。表头带单位，贴进任何表格软件都能直接分列。
    var text: String {
        var out = "时间\t亮部%\t暗部%\t平均亮度%\t快门\t光圈\tISO\t焦距mm\t判断\n"
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        for r in records {
            out += f.string(from: r.at)
            out += String(format: "\t%.2f\t%.2f\t%.1f",
                          r.highlight * 100, r.shadow * 100, r.mean * 100)
            out += "\t\(r.shutter)\t\(r.aperture)\t\(r.iso)\t\(r.focalMM)\t\(r.verdict)\n"
        }
        return out
    }

    private func load() {
        guard let d = UserDefaults.standard.data(forKey: key) else { return }
        records = (try? JSONDecoder().decode([SampleRecord].self, from: d)) ?? []
    }

    private func save() {
        guard let d = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(d, forKey: key)
    }
}
