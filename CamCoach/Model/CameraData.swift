// SPDX-License-Identifier: Apache-2.0
import Foundation

// MARK: - 顶层

/// `Resources/camcoach-data.json` 的内存结构。
///
/// 这份 JSON 由 `_tests/build-ios-data.py` 从 `data/buttons.json` 加
/// 网页原型里的菜单索引、预设、连接检查合成。改内容改那个脚本，别直接
/// 改 JSON，否则下次重新生成会被覆盖。
struct CameraData: Decodable {
    let schemaVersion: Int
    let device: DeviceInfo
    let views: [BodyViewInfo]
    let levels: [String: String]
    let ptpObservableLevels: [String: String]
    let buttons: [ButtonInfo]
    let menus: [MenuEntry]
    let presets: [ShootingPreset]
    let connectChecks: [ConnectCheck]

    /// 某个视角下的按钮，顺序沿用 JSON 里排好的。
    /// 方法名没有沿用 `buttons(in:)` 是刻意的：属性也叫 buttons，
    /// 虽然 Swift 允许共存，但读代码时容易看错。
    func buttonsFor(view viewID: String) -> [ButtonInfo] {
        buttons.filter { $0.view == viewID }
    }

    func view(withID viewID: String) -> BodyViewInfo? {
        views.first { $0.id == viewID }
    }
}

// MARK: - 机型

/// 文案对应的机型与固件基线。
///
/// 菜单路径会随固件变。这组字段就是用来在界面上说清「以哪个版本为准」的，
/// 不然用户拿着旧固件找不到某一项，会以为是 App 写错了。
struct DeviceInfo: Decodable {
    let model: String
    let name: String
    let firmwareBaseline: String?
    let contentNote: String?
    let disclaimer: String?

    /// 一行标题，例如「ILCE-7M4 · 固件 Ver.6.02」。
    var shortLabel: String {
        if let fw = firmwareBaseline, !fw.isEmpty {
            return "\(model) · 固件 \(fw)"
        }
        return model
    }
}

// MARK: - 视角

struct BodyViewInfo: Decodable, Identifiable {
    let id: String
    let name: String
    let hint: String
}

// MARK: - 热区

/// 机身上的可点区域。坐标用的是 336×280 画布，跟网页原型一致。
struct Hotspot: Decodable {
    let shape: String          // "circle" 或 "rect"
    let cx: Double?
    let cy: Double?
    let r: Double?
    let x: Double?
    let y: Double?
    let w: Double?
    let h: Double?

    var isCircle: Bool { shape == "circle" }

    /// 圆的中心与半径，非圆返回 nil。
    var circle: (cx: Double, cy: Double, r: Double)? {
        guard isCircle, let cx = cx, let cy = cy, let r = r else { return nil }
        return (cx, cy, r)
    }

    /// 矩形的左上角与尺寸，非矩形返回 nil。
    var rect: (x: Double, y: Double, w: Double, h: Double)? {
        guard !isCircle, let x = x, let y = y, let w = w, let h = h else { return nil }
        return (x, y, w, h)
    }
}

// MARK: - 协议可读性

/// 这个键的动作能不能从相机里读到。决定以后要不要做实时校验。
struct PTPObservable: Decodable {
    let level: String          // full / partial / none
    let property: String?
    let note: String
}

// MARK: - 按钮

struct ButtonInfo: Decodable, Identifiable {
    let id: String
    let name: String
    let aliases: [String]
    let view: String
    let hotspot: Hotspot
    let level: String          // week1 / later
    let location: String
    let defaultText: String
    let whatItDoes: String
    let howToUse: String
    let whyItMatters: String
    let changeIt: String
    let misconception: String
    let ptpObservable: PTPObservable

    enum CodingKeys: String, CodingKey {
        case id, name, aliases, view, hotspot, level, location
        case defaultText = "default"
        case whatItDoes, howToUse, whyItMatters, changeIt, misconception, ptpObservable
    }
}

// MARK: - 菜单反查

struct MenuEntry: Decodable, Identifiable {
    var id: String { want }
    let want: String           // 用户想做的事
    let path: String           // 菜单路径
    let note: String           // 容易走错的地方
}

// MARK: - 预设

struct ShootingPreset: Decodable, Identifiable {
    var id: String { name }
    let name: String
    let desc: String
    let params: String
    let warn: String
    let steps: [String]
}

// MARK: - 连接前检查

struct ConnectCheck: Decodable, Identifiable {
    var id: String { title }
    let title: String
    let detail: String
}

// MARK: - 加载

enum CameraDataError: LocalizedError {
    case missingFile
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingFile:
            return "找不到 camcoach-data.json，它应该被打包进 App 里"
        case .decodeFailed(let why):
            return "数据文件解析失败：\(why)"
        }
    }
}

enum CameraDataStore {

    /// 只解一次。JSON 是静态的，没必要每次进页面都重读磁盘。
    static let shared: Result<CameraData, CameraDataError> = load()

    private static func load() -> Result<CameraData, CameraDataError> {
        guard let url = locate() else {
            return .failure(.missingFile)
        }
        do {
            let raw = try Data(contentsOf: url)
            let data = try JSONDecoder().decode(CameraData.self, from: raw)
            return .success(data)
        } catch {
            return .failure(.decodeFailed(error.localizedDescription))
        }
    }

    /// 打包方式不同，位置会不一样：XcodeGen 默认把文件平铺进 bundle 根，
    /// 但如果哪天 Resources 被当成 folder reference，就会带上子目录。
    /// 两种都试一下，省得因为目录结构改动就整页报错。
    private static func locate() -> URL? {
        Bundle.main.url(forResource: "camcoach-data", withExtension: "json")
            ?? Bundle.main.url(forResource: "camcoach-data",
                               withExtension: "json",
                               subdirectory: "Resources")
    }
}
