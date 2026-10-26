// SPDX-License-Identifier: Apache-2.0
import CoreImage
import UIKit

/// 一个风格的参数表。
///
/// 和「一个滤镜定死一个样」的区别就在这里：一个风格是**一组参数一起给值**。
/// 对比、饱和、色温、高光压多少、阴影提多少、四角压多暗，分开调、串起来，
/// 才有那个味道。相机厂和大疆那套风格包，结构也是这个。
struct Look: Equatable {
    /// 整体明暗，正数变亮。-0.3…0.3 够用，再大就灰了。
    var brightness: Double = 0
    /// 对比度，1 是不动。大于 1 反差变大，小于 1 发灰。
    var contrast: Double = 1
    /// 饱和度，1 是不动，0 是黑白。
    var saturation: Double = 1
    /// 冷暖。正数偏暖（加红减蓝），负数偏冷。-1…1。
    ///
    /// 这里没用 CITemperatureAndTint：那个滤镜的两个输入（neutral / targetNeutral）
    /// 到底哪个方向是暖，各家代码里写反的不少，我手上没真机验证不了方向。
    /// CIColorMatrix 直接给 R、B 两个通道的增益，方向是确定的，不会反。
    var warmth: Double = 0
    /// 高光压多少。0 不动，越大越把亮部往下压，天不会死白。
    var highlightCut: Double = 0
    /// 阴影提多少。0 不动，正数把暗部拉起来。
    var shadowLift: Double = 0
    /// 四角压暗，0 不加。
    var vignette: Double = 0
}

/// 一个可以套在画面上的风格。
///
/// 边界要说清楚：这些是 **App 内的后期处理**，不是相机的色彩风格。
/// 相机拍出来的 JPEG 该是什么样还是什么样，风格只影响两件事——
/// 你在手机上看到的预览，以及从这里存进相册的那一份。
///
/// 想改相机本身的直出色彩，得写机身的「创意风格 / Creative Look」，
/// 那是另一条路，得先验证写入命令通不通。
struct PhotoFilter: Identifiable, Equatable {
    let id: String
    let name: String
    /// 一句人话，说明这个风格适合什么时候用。
    let note: String
    let look: Look
}

/// 你在拍什么。
///
/// 用户不一定懂「色温」「曲线」这些词，但一定知道自己今天是拍人还是拍景。
/// 所以风格不按调色原理分类，按题材分：选一个题材，条上只剩跟它相关的几个。
///
/// 名字没叫 Scene，是因为 SwiftUI 里已经有个 Scene 协议，
/// 同一个文件里 import SwiftUI 时重名会报一堆看不懂的错。
enum ShootScene: String, CaseIterable, Identifiable {
    case all, portrait, landscape, city, night, food

    var id: String { rawValue }

    var name: String {
        switch self {
        case .all: return "全部"
        case .portrait: return "人像"
        case .landscape: return "风景"
        case .city: return "城市"
        case .night: return "夜景"
        case .food: return "食物"
        }
    }

    /// 选了这个题材之后，一句话说清它到底替你解决什么。
    ///
    /// 不写「肤色更好看」这种话——那是广告词，看不出该不该开。
    /// 写「额头不反光」，用户抬头看一眼画面就知道要不要用。
    var hint: String {
        switch self {
        case .all: return ""
        case .portrait: return "肤色不发脏，额头和鼻梁的反光不糊成白块"
        case .landscape: return "天不死白，云有层次，绿色不脏"
        case .city: return "墙和金属不泛黄，画面干净"
        case .night: return "路灯招牌不糊成白块，暗部沉得住"
        case .food: return "菜的颜色讨喜，但不会偏到变色"
        }
    }

    /// 这个题材下推荐哪几个风格，按推荐程度排。
    ///
    /// 「原色」永远放第一个：选了题材又想退回不调的样子，不用再切回「全部」。
    var ids: [String] {
        switch self {
        case .all: return Filters.all.map { $0.id }
        case .portrait: return ["none", "soft", "fresh", "warm", "fade"]
        case .landscape: return ["none", "clear", "cinema", "punch"]
        case .city: return ["none", "cool", "cinema", "film", "noir"]
        case .night: return ["none", "night", "cinema"]
        case .food: return ["none", "warm", "punch", "film"]
        }
    }
}

enum Filters {

    /// 内置风格。顺序按「从不动到动得多」排，用户横着扫一遍就能找到想要的。
    static let all: [PhotoFilter] = [
        PhotoFilter(id: "none", name: "原色",
                    note: "相机的样子，一点都不动",
                    look: Look()),

        PhotoFilter(id: "clear", name: "清透",
                    note: "亮一点、淡一点，白天出门最稳的一个",
                    look: Look(brightness: 0.04, contrast: 0.95, saturation: 0.90,
                               warmth: -0.12, highlightCut: 0.10, shadowLift: 0.08)),

        PhotoFilter(id: "fresh", name: "日系",
                    note: "低饱和、抬暗部，阴天和室内人像不容易脏",
                    look: Look(brightness: 0.06, contrast: 0.93, saturation: 0.84,
                               warmth: -0.22, highlightCut: 0.12, shadowLift: 0.05)),

        // 人像专用。对比压低是重点：皮肤的斑、阴影里的色块，都是对比拉出来的。
        // 高光再收一截，额头和鼻梁的反光不会糊成一片白。
        PhotoFilter(id: "soft", name: "柔光",
                    note: "拍人。对比压低、皮肤干净，额头反光不会糊成白块",
                    look: Look(brightness: 0.03, contrast: 0.94, saturation: 0.92,
                               warmth: 0.12, highlightCut: 0.18, shadowLift: 0.14)),

        PhotoFilter(id: "warm", name: "暖调",
                    note: "偏黄，傍晚、室内、吃的",
                    look: Look(brightness: 0.01, contrast: 1.04, saturation: 1.06,
                               warmth: 0.55)),

        PhotoFilter(id: "cool", name: "冷调",
                    note: "偏蓝，城市、金属、阴天",
                    look: Look(contrast: 1.03, saturation: 0.97, warmth: -0.55)),

        PhotoFilter(id: "cinema", name: "电影",
                    note: "反差大、饱和压下来、高光收住、四角压暗，画面立刻正经",
                    look: Look(brightness: -0.02, contrast: 1.14, saturation: 0.80,
                               warmth: 0.22, highlightCut: 0.28, shadowLift: 0.18,
                               vignette: 0.28)),

        // 夜景用。高光压得比「电影」更狠：路灯、招牌、橱窗是过曝的重灾区，
        // 不压下来整片就是白块。暗部再往下沉一点，画面才有夜的重量。
        PhotoFilter(id: "night", name: "夜灯",
                    note: "拍夜景。灯不糊成白块，暗部沉得住",
                    look: Look(brightness: -0.03, contrast: 1.16, saturation: 1.08,
                               warmth: 0.16, highlightCut: 0.34, shadowLift: -0.06,
                               vignette: 0.22)),

        PhotoFilter(id: "film", name: "胶片",
                    note: "褪了色又带点暖，老照片那股",
                    look: Look(brightness: 0.03, contrast: 0.90, saturation: 0.76,
                               warmth: 0.32, highlightCut: 0.12, shadowLift: 0.22,
                               vignette: 0.30)),

        PhotoFilter(id: "noir", name: "黑白",
                    note: "反差高，光影比颜色重要的时候用",
                    look: Look(contrast: 1.22, saturation: 0, vignette: 0.30)),

        PhotoFilter(id: "punch", name: "浓烈",
                    note: "加对比加饱和，色彩冲击强",
                    look: Look(contrast: 1.18, saturation: 1.30, vignette: 0.14)),

        PhotoFilter(id: "fade", name: "褪色",
                    note: "对比压低，雾蒙蒙的",
                    look: Look(brightness: 0.05, contrast: 0.82, saturation: 0.74,
                               highlightCut: 0.06, vignette: 0.12)),
    ]

    /// 导入的 .cube 调色包，前缀统一是 `lut:`，后面跟名字。
    ///
    /// 用前缀而不是另建一个列表，是因为这个 id 一路要传进取景循环
    /// （`LiveSession.setFilter`）。两种来源共用同一个字符串通道，
    /// 循环里只看前缀决定走哪条渲染路径，不关心它从哪来。
    static let lutPrefix = "lut:"

    static func fromLUT(name: String) -> PhotoFilter {
        PhotoFilter(id: lutPrefix + name, name: name,
                    note: "你自己导入的调色包", look: Look())
    }

    static func find(_ id: String) -> PhotoFilter {
        if let hit = all.first(where: { $0.id == id }) { return hit }
        if id.hasPrefix(lutPrefix) {
            return fromLUT(name: String(id.dropFirst(lutPrefix.count)))
        }
        return all[0]
    }

    static func isLUT(_ id: String) -> Bool {
        id.hasPrefix(lutPrefix)
    }

    /// 某个题材下该显示哪些风格。
    ///
    /// `keeping` 是当前已经选中的那个。如果它不在这个题材的推荐里，
    /// 也要插到最前面留着——否则一切题材，用户明明选着「夜灯」，
    /// 条上却一个都没高亮，会以为选择被重置了。
    static func forScene(_ scene: ShootScene, keeping id: String) -> [PhotoFilter] {
        if scene == .all { return all }
        var list = scene.ids.map { find($0) }
        if id != "none", !isLUT(id), !scene.ids.contains(id) {
            list.insert(find(id), at: 0)
        }
        return list
    }
}

/// 把风格真正画出来。
///
/// 只用一个 CIContext，全 App 共用。每帧新建一个会把 GPU 上下文反复初始化，
/// 取景只有 10fps，光这一项就够把帧率拖下去。
final class FilterEngine {

    static let shared = FilterEngine()

    private let context = CIContext()

    private init() {}

    /// 套风格。ID 是原色、或者强度接近 0 时直接把原图退回去，不做任何 GPU 工作。
    func apply(id: String, to image: UIImage, strength: Double) -> UIImage {
        guard id != "none", strength > 0.01 else { return image }
        guard let cg = image.cgImage else { return image }

        let input = CIImage(cgImage: cg)

        // 两条路：内置风格走参数串，导入的调色包走 3D LUT。
        let styled: CIImage?
        if Filters.isLUT(id) {
            styled = lutStyle(String(id.dropFirst(Filters.lutPrefix.count)), input)
        } else {
            styled = lookStyle(Filters.find(id).look, input)
        }
        guard let styled else { return image }

        let s = min(max(strength, 0), 1)
        // strength = 1 时不必走混合，省一次渲染。
        if s >= 0.99 {
            return render(styled, extent: input.extent) ?? image
        }
        // CIDissolveTransition 的 time 是「朝 target 走多少」，
        // 我们的 strength 是「像风格多少」，所以取 1 - s。
        let blended = styled.applyingFilter("CIDissolveTransition", parameters: [
            kCIInputTargetImageKey: input,
            kCIInputTimeKey: 1.0 - s,
        ])
        return render(blended, extent: input.extent) ?? image
    }

    private func render(_ image: CIImage, extent: CGRect) -> UIImage? {
        guard let cg = context.createCGImage(image, from: extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: - 内置风格

    /// 参数按「先颜色、再明暗、最后四角」的顺序串。
    ///
    /// 顺序是有讲究的：亮度/对比先做，高低光才有东西可压；
    /// 暗角放最后，否则前面抬亮的动作会把压下去的角又提回来。
    ///
    /// 全部用系统内置滤镜，不写自定义 kernel：
    /// 自定义 kernel 在真机上一旦有编译问题就是黑屏，而内置滤镜的
    /// 行为和色彩管理都是系统管着的，稳得多。
    private func lookStyle(_ look: Look, _ input: CIImage) -> CIImage? {
        var img = input

        let hasColor = abs(look.brightness) > 0.001
            || abs(look.contrast - 1) > 0.001
            || abs(look.saturation - 1) > 0.001
            || abs(look.warmth) > 0.001

        if hasColor {
            img = img.applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: look.brightness,
                kCIInputContrastKey: look.contrast,
                kCIInputSaturationKey: look.saturation,
            ])

            // 冷暖单独一步：R 加多少、B 减多少是确定的，不像色温滤镜会给反。
            if abs(look.warmth) > 0.001 {
                let r = 1 + 0.06 * look.warmth
                let b = 1 - 0.06 * look.warmth
                img = img.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: r, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                    "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                ])
            }
        }

        // 高光和阴影用色调曲线做，不用 CIHighlightShadowAdjust。
        // 后者的 highlightAmount / shadowAmount 对这张 1024×680 的取景帧
        // 到底吃多深不好估；曲线是五个点直接写出来，输出在哪是能算的。
        if look.highlightCut > 0.001 || abs(look.shadowLift) > 0.001 {
            let lift = look.shadowLift
            let cut = look.highlightCut
            // 四段都夹住，保证曲线严格递增——不递增 CIImage 会画出一块死色。
            let p0 = max(0.0, min(0.20, lift * 0.25))
            let p1 = max(0.10, min(0.45, 0.25 + lift * 0.20))
            let p3 = max(0.55, min(0.90, 0.75 - cut * 0.20))
            let p4 = max(0.60, min(1.00, 1.00 - cut * 0.28))
            img = img.applyingFilter("CIToneCurve", parameters: [
                "inputPoint0": CIVector(x: 0.00, y: p0),
                "inputPoint1": CIVector(x: 0.25, y: p1),
                "inputPoint2": CIVector(x: 0.50, y: 0.50),
                "inputPoint3": CIVector(x: 0.75, y: p3),
                "inputPoint4": CIVector(x: 1.00, y: p4),
            ])
        }

        if look.vignette > 0.001 {
            img = img.applyingFilter("CIVignette", parameters: [
                "inputIntensity": look.vignette,
                "inputRadius": 1.5,
            ])
        }

        return img
    }

    // MARK: - 导入的 LUT

    /// 套 3D LUT。
    ///
    /// 这是「大疆那种调色」最接近的形态：一个 .cube 文件里存着
    /// 「这个颜色该变成哪个颜色」的对照表，和厂家风格包用的是同一套东西。
    /// 好处是不用我自己猜参数，别人调好的罐子直接能用。
    private func lutStyle(_ name: String, _ input: CIImage) -> CIImage? {
        guard let cube = LUTStore.shared.cube(named: name) else { return nil }
        // 色彩空间要显式给 sRGB：不给的话 CoreImage 会拿工作空间去解释
        // cube 里的数值，同一份 LUT 在别的软件里和在这里颜色会不一样。
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return input.applyingFilter("CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": cube.size,
            "inputCubeData": cube.data,
            "inputColorSpace": space,
        ])
    }
}
