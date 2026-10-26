// SPDX-License-Identifier: Apache-2.0
import Foundation

/// PTP 的 GetDeviceInfo（0x1001）回包。
///
/// 这个查询不需要索尼认证，所以它在排查链上位置很特殊：
/// 只要能读出厂商 ID 和型号字符串，就同时证明了三件事——
/// USB 枚举通了、会话通了、命令通道通了。
/// 后面读不到参数就只可能是认证或属性解析的问题，不用再往物理层找。
///
/// 结构按 ISO 15740 固定顺序，全部小端：
///   StandardVersion(u16) VendorExtensionID(u32) VendorExtensionVersion(u16)
///   VendorExtensionDesc(字符串) FunctionalMode(u16)
///   OperationsSupported / EventsSupported / DevicePropertiesSupported /
///   CaptureFormats / ImageFormats —— 五个「u32 个数 + u16 数组」
///   Manufacturer / Model / DeviceVersion / SerialNumber —— 四个字符串
///
/// 字符串是 PTP 的格式：一个 u16 表示字符数（含结尾 0），随后是 UTF-16LE。
struct SonyDeviceInfo {

    let standardVersion: UInt16
    let vendorExtensionID: UInt32
    let vendorExtensionVersion: UInt16
    let functionalMode: UInt16
    let manufacturer: String
    let model: String
    let deviceVersion: String
    let serial: String
    let operationCount: Int
    let propertyCount: Int

    /// 厂商扩展 ID 0x11 是索尼在全球注册的号。读到它基本就确认对面是索尼机身。
    var vendorLabel: String {
        switch vendorExtensionID {
        case 0x0000_0011: return "索尼 0x00000011"
        case 0x0000_0000: return "无厂商扩展（纯标准 PTP）"
        default: return String(format: "0x%08X", vendorExtensionID)
        }
    }

    var modelLabel: String {
        let m = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return m.isEmpty ? "未提供" : m
    }

    /// 能不能发索尼私有命令。ID 不对就一定读不到 D2xx。
    var isSony: Bool { vendorExtensionID == 0x0000_0011 }

    static func parse(_ data: Data) -> SonyDeviceInfo? {
        let b = [UInt8](data)
        guard b.count >= 12 else { return nil }

        var i = 0
        func u16() -> UInt16? {
            guard i + 1 < b.count else { return nil }
            let v = UInt16(b[i]) | (UInt16(b[i + 1]) << 8)
            i += 2
            return v
        }
        func u32() -> UInt32? {
            guard i + 3 < b.count else { return nil }
            let v = UInt32(b[i]) | (UInt32(b[i + 1]) << 8)
                | (UInt32(b[i + 2]) << 16) | (UInt32(b[i + 3]) << 24)
            i += 4
            return v
        }
        func string() -> String? {
            guard let n = u16() else { return nil }
            guard n > 0 else { return "" }
            let bytes = Int(n) * 2
            guard i + bytes <= b.count else { return nil }
            var units: [UInt16] = []
            units.reserveCapacity(Int(n))
            var k = i
            while k + 1 < i + bytes {
                units.append(UInt16(b[k]) | (UInt16(b[k + 1]) << 8))
                k += 2
            }
            i += bytes
            if units.last == 0 { units.removeLast() }
            return String(decoding: units, as: UTF16.self)
        }
        /// 数组是「u32 个数 + 每个 2 字节」，跳过但把个数记下来。
        func skipArray() -> Int? {
            guard let n = u32() else { return nil }
            let bytes = Int(n) * 2
            guard i + bytes <= b.count else { return nil }
            i += bytes
            return Int(n)
        }

        let std = u16() ?? 0
        let vid = u32() ?? 0
        let vver = u16() ?? 0
        _ = string()                       // VendorExtensionDesc
        let mode = u16() ?? 0
        let ops = skipArray() ?? 0
        _ = skipArray()                    // EventsSupported
        let props = skipArray() ?? 0
        _ = skipArray()                    // CaptureFormats
        _ = skipArray()                    // ImageFormats
        let maker = string() ?? ""
        let model = string() ?? ""
        let version = string() ?? ""
        let serial = string() ?? ""

        return SonyDeviceInfo(
            standardVersion: std,
            vendorExtensionID: vid,
            vendorExtensionVersion: vver,
            functionalMode: mode,
            manufacturer: maker,
            model: model,
            deviceVersion: version,
            serial: serial,
            operationCount: ops,
            propertyCount: props
        )
    }
}
