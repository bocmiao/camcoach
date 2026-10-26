// SPDX-License-Identifier: Apache-2.0
import UIKit

/// 一条建议。全部本地算，不联网、不调模型。
struct Advice: Identifiable {

    enum Level {
        case good, warn, bad
    }

    let id = UUID()
    let level: Level
    let text: String
    let detail: String
}

/// 曝光统计。从取景帧上直接算，不依赖相机的测光结果。
struct ExposureStats {
    /// 接近纯白的像素比例。
    let highlight: Double
    /// 接近纯黑的像素比例。
    let shadow: Double
    /// 平均亮度 0...1。
    let mean: Double
}

enum Advisor {

    /// 把取景帧缩到 64×64 灰度图再统计。
    ///
    /// 不需要全分辨率：判断过曝只看比例，而 1024×680 每次重算会拖慢帧率。
    static func exposure(_ image: UIImage) -> ExposureStats? {
        guard let cg = image.cgImage else { return nil }
        let side = 64
        let count = side * side
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        defer { buf.deallocate() }

        guard let ctx = CGContext(data: buf, width: side, height: side,
                                  bitsPerComponent: 8, bytesPerRow: side,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return nil
        }
        ctx.interpolationQuality = .low
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))

        var highlight = 0
        var shadow = 0
        var sum = 0
        for i in 0..<count {
            let v = Int(buf[i])
            sum += v
            if v >= 250 { highlight += 1 }
            if v <= 8 { shadow += 1 }
        }
        return ExposureStats(
            highlight: Double(highlight) / Double(count),
            shadow: Double(shadow) / Double(count),
            mean: Double(sum) / Double(count) / 255
        )
    }

    /// 给新手看的三条以内的建议。
    ///
    /// 判断顺序就是「拍废一张照片最常见的原因」的顺序：
    /// 过曝 → 跑焦 → 手抖 → 噪点。暗部的问题排在后面，
    /// 因为欠曝还能拉回来，死白拉不回来。
    static func review(_ r: CameraReadout, exposure: ExposureStats?) -> [Advice] {
        var out: [Advice] = []

        if let e = exposure {
            if e.highlight > 0.02 {
                out.append(Advice(
                    level: .bad,
                    text: "亮部已经死白",
                    detail: String(format: "画面里 %.0f%% 的像素接近纯白，这些地方后期拉不回来。曝光补偿往负方向调一档。",
                                   e.highlight * 100)))
            } else if e.highlight > 0.006 {
                out.append(Advice(
                    level: .warn,
                    text: "亮部快到头了",
                    detail: "接近纯白的像素已经有一点多，拍高反差场景建议先减 0.3 EV 保险。"))
            }

            if e.shadow > 0.35 {
                out.append(Advice(
                    level: .warn,
                    text: "暗部糊成一片",
                    detail: String(format: "%.0f%% 的像素接近纯黑。如果不是拍剪影或夜景，试着加曝光或补光。",
                                   e.shadow * 100)))
            }
        }

        if r.focus == "未合焦" {
            out.append(Advice(
                level: .bad,
                text: "没合上焦",
                detail: "相机报告的合焦状态还是进行中。半按快门重新对，或者确认对焦点落在主体上。"))
        }

        if let s = r.shutterSeconds, s > 1.0 / 50 {
            out.append(Advice(
                level: .warn,
                text: "快门偏慢，手持容易抖",
                detail: "现在 \(r.shutter)。手持拍静态物体，1/60 以上更稳；抓拍人像或小孩要 1/125 以上。"))
        }

        if let iso = r.isoValue, iso >= 3200 {
            out.append(Advice(
                level: .warn,
                text: "ISO 偏高",
                detail: "现在 ISO \(Int(iso))。A7M4 到这个档位噪点开始明显，能开大光圈或补光就往下压。"))
        }

        if out.isEmpty {
            let mean = exposure.map { String(format: "平均亮度 %.0f%%", $0.mean * 100) } ?? "没算曝光"
            out.append(Advice(
                level: .good,
                text: "参数没问题，可以按快门",
                detail: "\(r.shutter) · \(r.aperture) · ISO \(r.iso) · \(mean)"))
        }

        return Array(out.prefix(3))
    }
}
