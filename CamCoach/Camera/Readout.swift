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
        }

        if let v = SonySDIO.scalar(props, CameraProp.iso) {
            r.iso = Self.isoText(v)
            r.isoValue = Self.isoNumber(v)
        }

        if let v = SonySDIO.scalar(props, CameraProp.fNumber) {
            r.aperture = Self.fNumberText(v)
        }

        if let v = SonySDIO.scalar(props, CameraProp.exposureComp) {
            r.exposureComp = Self.evText(v)
        }

        if let v = SonySDIO.scalar(props, CameraProp.exposureProgram) {
            r.mode = Self.modeText(v)
        }

        if let v = SonySDIO.scalar(props, CameraProp.focusFound) {
            // 2 = 合焦，3 = 合焦（AF-S 锁定）；1 = 还没合上。
            switch v {
            case 2, 3: r.focus = "合焦"
            default: r.focus = "未合焦"
            }
        }

        if let v = SonySDIO.scalar(props, CameraProp.battery) {
            r.battery = Self.percentText(v)
        }

        if let v = SonySDIO.scalar(props, CameraProp.shotsSlot1) {
            r.shotsLeft = v > 0 ? "\(v)" : "—"
        }

        if let v = SonySDIO.scalar(props, CameraProp.liveView) {
            r.liveViewOn = v != 0
        }

        return r
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

    /// 标准 PTP 的曝光模式：1 手动 / 2 程序 / 3 光圈优先 / 4 快门优先。
    /// 索尼机身的编号与之相同，但这台机型的实测还没覆盖全，界面上只给字母。
    static func modeText(_ raw: Int64) -> String {
        switch raw {
        case 1: return "M"
        case 2: return "P"
        case 3: return "A"
        case 4: return "S"
        default: return "—"
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
