// SPDX-License-Identifier: Apache-2.0
import Foundation

/// 索尼 SDIO 属性块的解析。
///
/// 相机用 `0x9209`（SDIO_GetAllExtDevicePropInfo）一次性吐回**全部**属性，
/// 结构是「元素个数 + 记录数组」，每条记录自带数据类型和长度，
/// 所以必须按类型逐字段走位，不能按固定偏移猜。
///
/// 之前用标准 PTP 的 `GetDevicePropValue(0x1015)` 配 `0x500F`（ISO）这类码，
/// 对索尼机身是读不到的：索尼把绝大多数参数放在自己的 `0xD2xx` 段，
/// 只认这一个整块读取。
enum SonySDIO {

    /// 属性当前能不能用。
    ///
    /// 「不支持这条」和「这条在当前模式下无效」是两件事，
    /// 界面上该说的话完全不一样。
    enum Availability {
        /// IsEnabled = 0，机身有这条，但当前模式下无效。
        case disabled
        /// IsEnabled = 1，可读；writable 时也可写。
        case enabled
        /// IsEnabled = 2，只用于显示，不能写。
        case displayOnly
    }

    /// 一个属性值。对应 PTP 的数据类型空间。
    indirect enum Value: Equatable {
        case integer(Int64)
        case text(String)
        case array([Value])
        case opaque(String)

        var int: Int64? {
            if case let .integer(v) = self { return v }
            return nil
        }

        var display: String {
            switch self {
            case let .integer(v): return "\(v)"
            case let .text(v): return v
            case let .array(v): return "[" + v.map(\.display).joined(separator: ",") + "]"
            case let .opaque(v): return "0x" + v
            }
        }
    }

    struct ValueRange: Equatable {
        let min: Value
        let max: Value
        let step: Value
    }

    /// 一条属性。
    struct Property: Equatable {
        let code: UInt16
        let dataType: UInt16
        let writable: Bool
        let availability: Availability
        let current: Value
        let range: ValueRange?
        /// 当前模式下可选的取值列表（枚举型属性才有）。
        let settable: [Value]

        var enabled: Bool { availability != .disabled }
        var label: String { String(format: "0x%04X", code) }
    }

    // MARK: - 入口

    /// 解析 `0x9209` 的返回数据。
    ///
    /// 数据被截断时返回已经完整解析出来的前缀，而不是整体丢掉：
    /// 前面几十条属性通常都是有效的。
    static func parseAll(_ data: Data) -> [Property] {
        var r = Reader(data)
        var out: [Property] = []
        do {
            let declared = try r.u64()
            let count = (declared <= 0 || declared > 4096) ? 4096 : declared
            var i: Int64 = 0
            while i < count, r.remaining > 0 {
                out.append(try record(&r))
                i += 1
            }
        } catch {
            // 走到这里说明后面残缺了，前缀仍然可用。
        }
        return out
    }

    static func find(_ props: [Property], _ code: UInt16) -> Property? {
        props.first { $0.code == code }
    }

    /// 取一条属性的整数值。轮询 D213 / D215 / D221 时用。
    static func scalar(_ props: [Property], _ code: UInt16) -> Int64? {
        find(props, code)?.current.int
    }

    private static func record(_ r: inout Reader) throws -> Property {
        let code = try r.u16()
        let dataType = try r.u16()
        let getSet = try r.u8()
        let isEnabled = try r.u8()
        _ = try r.value(dataType)              // Factory Default，跳过但必须走位
        let current = try r.value(dataType)
        let formFlag = try r.u8()

        var range: ValueRange?
        var settable: [Value] = []
        switch formFlag {
        case 0x01:
            range = ValueRange(min: try r.value(dataType),
                          max: try r.value(dataType),
                          step: try r.value(dataType))
        case 0x02:
            settable = try r.valueList(dataType)
            // 索尼在后面还跟一份 supported 列表，部分固件没有。
            if r.remaining >= 2 { _ = try? r.valueList(dataType) }
        default:
            break
        }

        let availability: Availability
        switch isEnabled {
        case 0: availability = .disabled
        case 2: availability = .displayOnly
        default: availability = .enabled
        }

        return Property(code: code, dataType: dataType, writable: getSet == 1,
                        availability: availability, current: current,
                        range: range, settable: settable)
    }

    // MARK: - 小端读取器

    /// 逐字段前进的游标。每个字段按真实宽度走位，
    /// 这是能顺序解析记录的前提：读错一个宽度，后面全乱。
    struct Reader {
        private let bytes: [UInt8]
        private var offset = 0

        init(_ data: Data) { bytes = [UInt8](data) }

        var remaining: Int { bytes.count - offset }

        mutating func take(_ n: Int) throws -> [UInt8] {
            guard n >= 0, offset + n <= bytes.count else {
                throw SDIOError.truncated(offset, bytes.count)
            }
            defer { offset += n }
            return Array(bytes[offset..<(offset + n)])
        }

        mutating func u8() throws -> UInt8 { try take(1)[0] }

        mutating func u16() throws -> UInt16 {
            let b = try take(2)
            return UInt16(b[0]) | (UInt16(b[1]) << 8)
        }

        mutating func u32() throws -> Int64 {
            let b = try take(4)
            var v: Int64 = 0
            for i in stride(from: 3, through: 0, by: -1) { v = (v << 8) | Int64(b[i]) }
            return v
        }

        mutating func u64() throws -> Int64 {
            let b = try take(8)
            var v: UInt64 = 0
            for i in stride(from: 7, through: 0, by: -1) { v = (v << 8) | UInt64(b[i]) }
            return Int64(bitPattern: v)
        }

        mutating func value(_ dataType: UInt16) throws -> Value {
            switch dataType {
            case 0x0001: return .integer(signed(Int64(try u8()), bits: 8))
            case 0x0002: return .integer(Int64(try u8()))
            case 0x0003: return .integer(signed(Int64(try u16()), bits: 16))
            case 0x0004: return .integer(Int64(try u16()))
            case 0x0005: return .integer(signed(try u32(), bits: 32))
            case 0x0006: return .integer(try u32())
            case 0x0007, 0x0008: return .integer(try u64())
            case 0x0009, 0x000A: return .opaque(try take(16).reversed().map { String(format: "%02X", $0) }.joined())
            case 0xFFFF: return .text(try ptpString())
            default:
                guard dataType & 0x4000 != 0 else {
                    throw SDIOError.unknownType(dataType)
                }
                let count = try u32()
                guard count >= 0, count <= 65536 else { throw SDIOError.badCount(count) }
                var items: [Value] = []
                for _ in 0..<count { items.append(try value(dataType & ~0x4000)) }
                return .array(items)
            }
        }

        mutating func valueList(_ dataType: UInt16) throws -> [Value] {
            let count = Int(try u16())
            guard count <= 65536 else { throw SDIOError.badCount(Int64(count)) }
            var items: [Value] = []
            items.reserveCapacity(count)
            for _ in 0..<count { items.append(try value(dataType)) }
            return items
        }

        /// PTP 字符串：1 字节字符数，然后那么多 UTF-16LE 码元（含结尾 0）。
        private mutating func ptpString() throws -> String {
            let chars = Int(try u8())
            if chars == 0 { return "" }
            let b = try take(chars * 2)
            let s = String(data: Data(b), encoding: .utf16LittleEndian) ?? ""
            return s.trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
        }

        private func signed(_ raw: Int64, bits: Int) -> Int64 {
            let sign: Int64 = 1 << (bits - 1)
            return (raw & sign) != 0 ? raw - (1 << bits) : raw
        }
    }

    enum SDIOError: LocalizedError {
        case truncated(Int, Int)
        case unknownType(UInt16)
        case badCount(Int64)

        var errorDescription: String? {
            switch self {
            case let .truncated(at, total): return "属性块在 \(at)/\(total) 字节处断了"
            case let .unknownType(t): return String(format: "没见过这个 PTP 数据类型 0x%04X", t)
            case let .badCount(n): return "数组长度 \(n) 不合理"
            }
        }
    }
}
