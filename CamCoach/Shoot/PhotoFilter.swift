// SPDX-License-Identifier: Apache-2.0
import CoreImage
import UIKit

/// 一组可以直接套在画面上的色调。
///
/// 边界要说清楚：这些是 **App 内的后期处理**，不是相机的色彩风格。
/// 相机拍出来的 JPEG 该是什么样还是什么样，滤镜只影响两件事——
/// 你在手机上看到的预览，以及从这里存进相册的那一份。
///
/// 想改相机本身的直出色彩，得写机身的「创意风格 / Creative Look」，
/// 那是另一条路，得先验证写入命令通不通。
struct PhotoFilter: Identifiable, Equatable {
    let id: String
    let name: String
    /// 一句人话，说明这个风格适合什么时候用。
    let note: String
}

enum Filters {

    static let all: [PhotoFilter] = [
        PhotoFilter(id: "none", name: "原色", note: "相机的样子，不加工"),
        PhotoFilter(id: "clear", name: "清透", note: "亮一点、淡一点，白天出门常用"),
        PhotoFilter(id: "warm", name: "暖调", note: "偏黄，傍晚、室内、吃的"),
        PhotoFilter(id: "cool", name: "冷调", note: "偏蓝，阴天、城市、金属"),
        PhotoFilter(id: "film", name: "胶片", note: "褪了色又带点暖，老照片的感觉"),
        PhotoFilter(id: "noir", name: "黑白", note: "高反差黑白，光影比颜色重要的时候用"),
        PhotoFilter(id: "punch", name: "浓烈", note: "加对比加饱和，色彩冲击强"),
        PhotoFilter(id: "fade", name: "褪色", note: "对比压低，雾蒙蒙的"),
    ]

    static func find(_ id: String) -> PhotoFilter {
        all.first { $0.id == id } ?? all[0]
    }
}

/// 把滤镜真正画出来。
///
/// 只用一个 CIContext，全 App 共用。每帧新建一个会把 GPU 上下文反复初始化，
/// 取景只有 10fps，光这一项就够把帧率拖下去。
final class FilterEngine {

    static let shared = FilterEngine()

    private let context = CIContext()

    private init() {}

    /// 套滤镜。强度和 ID 都没实际效果时直接把原图退回去，不做任何 GPU 工作。
    func apply(id: String, to image: UIImage, strength: Double) -> UIImage {
        guard id != "none", strength > 0.01 else { return image }
        guard let cg = image.cgImage else { return image }

        let input = CIImage(cgImage: cg)
        guard let styled = style(id, input) else { return image }

        let s = min(max(strength, 0), 1)
        // strength = 1 时不必走混合，省一次渲染。
        if s >= 0.99 {
            return render(styled, extent: input.extent) ?? image
        }
        // CIDissolveTransition 的 time 是「朝 target 走多少」，
        // 我们的 strength 是「像滤镜多少」，所以取 1 - s。
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

    /// 各个风格的具体做法。
    ///
    /// 全部用系统内置滤镜拼，不写自定义 kernel：
    /// 自定义 kernel 在真机上一旦有编译问题就是黑屏，而内置滤镜的
    /// 行为和色彩管理都是系统管着的，稳得多。
    private func style(_ id: String, _ input: CIImage) -> CIImage? {
        switch id {
        case "clear":
            return input.applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: 0.05,
                kCIInputContrastKey: 0.95,
                kCIInputSaturationKey: 0.90,
            ])
        case "warm":
            return input.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: 5400, y: 0),
            ])
        case "cool":
            return input.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: 7800, y: 0),
            ])
        case "film":
            return input.applyingFilter("CIPhotoEffectTransfer")
        case "noir":
            return input.applyingFilter("CIPhotoEffectNoir")
        case "punch":
            return input.applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 1.18,
                kCIInputSaturationKey: 1.30,
            ])
        case "fade":
            return input.applyingFilter("CIPhotoEffectFade")
        default:
            return nil
        }
    }
}
