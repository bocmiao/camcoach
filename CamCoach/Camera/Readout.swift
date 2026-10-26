// SPDX-License-Identifier: Apache-2.0
import Foundation

/// 从相机读回来的一屏参数。
///
/// 只放**确定能解码**的项。每种编码方式都对着 libgphoto2 里索尼机身的实现写过
/// （ptp2/config.c 的 `_get_Sony_ShutterSpeed` / `_stringify_Sony_ISO` /
/// `_get_Sony_FNumber` / `_get_ExpCompensation`），不是按心意猜的。
struct CameraReadout: Equatable {

    var shutter = "—"
    var aperture = "—"
    var iso = "—"
    var exposureComp = "—"
    var mode = "—"
    var focus = "—"
    var battery = "—"
    var shotsLeft = "—"
    var liveViewOn = false
    /// 快门折算成秒。判断「手持会不会抖」要用数值，不能用显示字符串。
    var shutterSeconds: Double?
    /// ISO 数值，用来判断噪点风险。
    var isoValue: Double?
    /// 这轮读回多少条属性。0 说明整块没读到。
    var propertyCount = 0
    /// 这台机身没通过 PTP 报出来的项（显示名）。
    ///
    /// 「读不到」和「读到了但是 0」是两件完全不同的事，界面上必须分开说：
    /// 前者是相机不给，后者是真的参数。把两者都显示成「—」，
    /// 用户会以为是 App 坏了，然后一路去查线。
    var missingFields: [String] = []

    static let empty = CameraReadout()
}

/// 索尼 SDIO 属性码。
///
/// 两段要分开看：`0xD2xx` 是索尼私有段，只能通过 `0x9209` 整块读；
/// 光圈、曝光模式这些仍在标准 PTP 段（`0x50xx`），同一块里也有。
enum CameraProp {
    static let shutter: UInt16 = 0xD20D
    static let shutter2: UInt16 = 0xD229
    static let iso: UInt16 = 0xD21E
    static let exposureComp: UInt16 = 0xD224
    static let focusFound: UInt16 = 0xD213
    static let battery: UInt16 = 0xD218
    static let shotsSlot1: UInt16 = 0xD249
    static let liveView: UInt16 = 0xD221

    static let fNumber: UInt16 = 0x5007
    static let exposureProgram: UInt16 = 0x500E
    /// 曝光补偿的标准 PTP 码（ExposureBiasCompensation，INT16，单位 1/1000 EV）。
    ///
    /// 索尼多数机身用私有段 `0xD224`，但也有机身把补偿留在标准段。
    /// 两个都试一遍，比赌一个码可靠——反正读不到只是多花 5 毫秒。
    static let exposureCompStd: UInt16 = 0x5010
    /// 标准 PTP 的曝光时间。少数机身只报这一条，不报 `0xD20D`。
    static let exposureTimeStd: UInt16 = 0x500D
}

// MARK: - 解码

extension CameraReadout {

    /// 从一整块属性构建。
    static func decode(_ props: [SonySDIO.Property]) -> CameraReadout {
        var r = CameraReadout()
        r.propertyCount = props.count

        if let v = SonySDIO.scalar(props, CameraProp.shutter) {
            r.shutter = Self.shutterText(v)
            r.shutterSeconds = Self.shutterSeconds(v)
        } else if let v = SonySDIO.scalar(props, CameraProp.shutter2) {
            // 少数机身把快门放在 0xD229（只在 mode 2 下有效）。
            r.shutter = Self.shutterText(v)
            r.shutterSeconds = Self.shutterSeconds(v)
        } else {
            r.missingFields.append("快门")
        }

        if let v = SonySDIO.scalar(props, CameraProp.iso) {
            r.iso = Self.isoText(v)
            r.isoValue = Self.isoNumber(v)
        } else {
            r.missingFields.append("ISO")
        }

        if let v = SonySDIO.scalar(props, CameraProp.fNumber) {
            r.aperture = Self.fNumberText(v)
        } else {
            r.missingFields.append("光圈")
        }

        if let v = SonySDIO.scalar(props, CameraProp.exposureComp) {
            r.exposureComp = Self.evText(v)
        } else if let v = SonySDIO.scalar(props, CameraProp.exposureCompStd) {
            r.exposureComp = Self.evText(v)
        } else {
            r.missingFields.append("补偿")
        }

        if let v = SonySDIO.scalar(props, CameraProp.exposureProgram) {
            r.mode = Self.modeText(v)
        } else {
            r.missingFields.append("模式")
        }

        if let v = SonySDIO.scalar(props, CameraProp.focusFound) {
            // 2 = 合焦，3 = 合焦（AF-S 锁定）；1 = 还没合上。
            switch v {
            case 2, 3: r.focus = "合焦"
            default: r.focus = "未合焦"
            }
        } else {
            r.missingFields.append("对焦")
        }

        if let v = SonySDIO.scalar(props, CameraProp.battery) {
            r.battery = Self.percentText(v)
        } else {
            r.missingFields.append("电量")
        }

        if let v = SonySDIO.scalar(props, CameraProp.shotsSlot1) {
            r.shotsLeft = v > 0 ? "\(v)" : "—"
        } else {
            r.missingFields.append("可拍")
        }

        if let v = SonySDIO.scalar(props, CameraProp.liveView) {
            r.liveViewOn = v != 0
        }

        return r
    }

    /// 单条读回来的 2 字节：按有符号解释。曝光补偿是 INT16，负数表示减曝光。
    static func signed16(_ d: Data) -> Int64? {
        guard d.count >= 2 else { return nil }
        let raw = UInt16(d[d.startIndex]) | (UInt16(d[d.startIndex + 1]) << 8)
        return Int64(Int16(bitPattern: raw))
    }

    /// 单条读回来的 2 字节：按无符号解释。曝光模式是 UINT16。
    static func unsigned16(_ d: Data) -> Int64? {
        guard d.count >= 2 else { return nil }
        return Int64(UInt16(d[d.startIndex]) | (UInt16(d[d.startIndex + 1]) << 8))
    }

    // MARK: 快门

    /// 索尼把快门速度打包成一个 UINT32：高 16 位分子、低 16 位分母。
    /// `1/250` 就是 `0x0001_00FA`。高速档会报成 `300/10` 这种，先约分。
    static func shutterSeconds(_ raw: Int64) -> Double? {
        let v = UInt32(truncatingIfNeeded: raw)
        var x = Int(v >> 16)
        var y = Int(v & 0xFFFF)
        if y == 10 && x % 10 == 0 {
            x /= 10
            y = 1
        }
        guard x > 0, y > 0 else { return nil }
        return Double(x) / Double(y)
    }

    static func shutterText(_ raw: Int64) -> String {
        guard let s = shutterSeconds(raw) else { return "—" }
        if s >= 1 {
            return trim(s) + "s"
        }
        return "1/\(Int((1 / s).rounded()))"
    }

    // MARK: ISO

    /// 低 24 位是基准 ISO，`0xFFFFFF` 表示自动；高 8 位是多帧降噪档位。
    static func isoNumber(_ raw: Int64) -> Double? {
        let v = UInt32(truncatingIfNeeded: raw)
        let base = v & 0x00FF_FFFF
        if base == 0x00FF_FFFF { return nil }
        return base > 0 ? Double(base) : nil
    }

    static func isoText(_ raw: Int64) -> String {
        let v = UInt32(truncatingIfNeeded: raw)
        let base = v & 0x00FF_FFFF
        if base == 0x00FF_FFFF { return "自动" }
        let nr = v >> 24
        if nr > 0 { return "\(base)+NR" }
        return "\(base)"
    }

    // MARK: 光圈

    /// UINT16，除以 100。`280` → `f/2.8`。
    static func fNumberText(_ raw: Int64) -> String {
        guard raw > 0 else { return "—" }
        return "f/" + trim(Double(raw) / 100)
    }

    // MARK: 曝光补偿

    /// INT16，除以 1000。`300` → `+0.3`。
    static func evText(_ raw: Int64) -> String {
        let ev = Double(raw) / 1000
        if abs(ev) < 0.05 { return "±0" }
        return (ev > 0 ? "+" : "") + trim(ev)
    }

    // MARK: 其它

    /// 标准 PTP 的曝光模式：1 手动 / 2 程序 / 3 光圈优先 / 4 快门优先，
    /// 5/6/7 是程序偏移、程序偏移（动作）、人像这三种旧定义。
    ///
    /// 认不出来的值**不回「—」**，直接显示成 `0x0010` 这样的原始值。
    /// 显示「—」等于把线索扔掉：既分不清「机身没报」和「报了但没认出来」，
    /// 也没法据此补表。把原始值显出来，下一版就能照着补。
    static func modeText(_ raw: Int64) -> String {
        switch raw {
        case 1: return "M"
        case 2, 5, 6, 7: return "P"
        case 3: return "A"
        case 4: return "S"
        default: return String(format: "0x%04X", UInt16(truncatingIfNeeded: raw))
        }
    }

    static func percentText(_ raw: Int64) -> String {
        guard raw >= 0, raw <= 100 else { return "—" }
        return "\(raw)%"
    }

    /// 去掉多余的小数位：2.0 → 2，0.3 → 0.3。
    static func trim(_ v: Double) -> String {
        if abs(v - v.rounded()) < 0.001 {
            return String(Int(v.rounded()))
        }
        let s = String(format: "%.1f", v)
        return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
    }
}
