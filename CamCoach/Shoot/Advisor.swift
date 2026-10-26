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

/// 一帧的亮度统计。从取景帧上直接算，不依赖相机的测光结果。
struct ExposureStats {
    /// 接近纯白的像素比例。
    let highlight: Double
    /// 接近纯黑的像素比例。
    let shadow: Double
    /// 平均亮度 0...1。
    let mean: Double
    /// 32 档亮度分布，每档是占全部像素的比例，加起来约等于 1。
    let histogram: [Double]
}

enum Advisor {

    /// 一帧算出来的全部东西。
    struct Analysis {
        let stats: ExposureStats
        /// 高光溢出的斜纹叠加图。画面里没有溢出时是 nil，
        /// 调用方据此决定要不要画这一层。
        let zebra: UIImage?
    }

    /// 把取景帧缩成 192×128 灰度图，一遍扫完出统计和斑马纹。
    ///
    /// 一次只画一次图：统计和斑马纹要的是同一份灰度数据，
    /// 分两次算等于把缩放多做一遍。10fps 下这点开销不算什么，
    /// 但没必要重复。
    ///
    /// 尺寸取 192×128 而不是原始 1024×680：判断溢出只看「哪一片过曝了」，
    /// 不需要像素级精度；斑马纹本来就是一格一格的斜纹，糊一点反而更像。
    static func analyze(_ image: UIImage) -> Analysis? {
        guard let cg = image.cgImage else { return nil }
        let w = 192
        let h = 128
        var gray = [UInt8](repeating: 0, count: w * h)

        let drawn = gray.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress,
                                      width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
                return false
            }
            ctx.interpolationQuality = .low
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }

        let total = w * h
        var bins = [Int](repeating: 0, count: 32)
        var hi = 0
        var lo = 0
        var sum = 0
        var rgba = [UInt8](repeating: 0, count: total * 4)
        var zebraDrawn = false

        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                let v = Int(gray[i])
                sum += v
                bins[min(31, v / 8)] += 1
                if v >= 250 { hi += 1 }
                if v <= 8 { lo += 1 }

                // 45° 斜纹：每 8 个像素一个周期，其中 4 个填红。
                // 用斜纹而不是整块半透明红，是因为整块红会让人误判「这一片就是这个颜色」，
                // 斜纹是「警告」的视觉约定，不会被当成画面内容。
                if v >= 250 && (x + y) % 8 < 4 {
                    let o = i * 4
                    rgba[o] = 235
                    rgba[o + 1] = 58
                    rgba[o + 2] = 58
                    rgba[o + 3] = 255
                    zebraDrawn = true
                }
            }
        }

        let stats = ExposureStats(
            highlight: Double(hi) / Double(total),
            shadow: Double(lo) / Double(total),
            mean: Double(sum) / Double(total) / 255,
            histogram: bins.map { Double($0) / Double(total) })

        guard zebraDrawn,
              let provider = CGDataProvider(data: Data(rgba) as CFData),
              let cgZebra = CGImage(width: w, height: h,
                                    bitsPerComponent: 8, bitsPerPixel: 32,
                                    bytesPerRow: w * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                    provider: provider, decode: nil,
                                    shouldInterpolate: false,
                                    intent: .defaultIntent)
        else {
            return Analysis(stats: stats, zebra: nil)
        }
        return Analysis(stats: stats, zebra: UIImage(cgImage: cgZebra))
    }

    /// 给新手看的三条以内的建议。
    ///
    /// 判断顺序就是「拍废一张照片最常见的原因」的顺序：
    /// 过曝 → 跑焦 → 手抖 → 噪点。暗部的问题排在后面，
    /// 因为欠曝还能拉回来，死白拉不回来。
    ///
    /// `focalMM` 是当前镜头的焦距，只用来算手持安全快门。
    /// 这个数拿不到真实的，用户在取景页自己选一档，比写死 1/50 靠谱：
    /// 24mm 端 1/50 稳得很，85mm 端 1/50 基本必糊。
    static func review(_ r: CameraReadout, exposure: ExposureStats?, focalMM: Int) -> [Advice] {
        var out: [Advice] = []

        if let e = exposure {
            if e.highlight > 0.02 {
                out.append(Advice(
                    level: .bad,
                    text: "亮部已经死白",
                    detail: String(format: "画面里 %.0f%% 的像素接近纯白，画面上叠红斜纹的地方就是。这些地方后期拉不回来，曝光补偿往负方向调一档。",
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

        if let s = r.shutterSeconds {
            let safe = 1.0 / Double(max(focalMM, 8))
            let safeText = "1/" + String(Int((1 / safe).rounded()))
            if s > safe * 2 {
                out.append(Advice(
                    level: .bad,
                    text: "这么慢的快门手持基本必糊",
                    detail: "现在 \(r.shutter)，\(focalMM)mm 的手持安全线是 \(safeText)，差了不止一档。"
                        + "开大光圈、提 ISO，或者把相机靠稳再拍。"))
            } else if s > safe {
                out.append(Advice(
                    level: .warn,
                    text: "快门低于安全线",
                    detail: "现在 \(r.shutter)，\(focalMM)mm 建议 \(safeText) 或更快。手持拍静态物体，再快一档更保险。"))
            }
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
