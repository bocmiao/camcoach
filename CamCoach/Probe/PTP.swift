// SPDX-License-Identifier: Apache-2.0
import Foundation

/// PTP（ISO 15740）的容器封装与索尼命令码。
///
/// 每个包结构都一样，全部小端：
///   Length(4) + Type(2) + Code(2) + TransactionID(4) + Params(4×N)
/// Length 算的是整个容器，不是 payload。
///
/// 命令码分两类：
///   · 0x1xxx 是标准 PTP
///   · 0x9xxx 是索尼私有（认证、控制、整块读属性）
/// 参数码（属性）分两类：
///   · 0x50xx 是标准 PTP 属性，索尼机身上大多读不到
///   · 0xD2xx 是索尼自己的属性，要通过 0x9209 整块读，不能单条读
///
/// 唯一的例外是写：写要用 `0x9205` 指定 0xD2xx 的码，data 就是值本身。
enum PTP {

    // ---- 标准 PTP
    static let getDeviceInfo: UInt16 = 0x1001
    static let openSession: UInt16 = 0x1002
    static let closeSession: UInt16 = 0x1003
    static let getObjectInfo: UInt16 = 0x1008
    static let getObject: UInt16 = 0x1009
    static let getDevicePropDesc: UInt16 = 0x1014
    static let getDevicePropValue: UInt16 = 0x1015
    static let setDevicePropValue: UInt16 = 0x1016

    // ---- 索尼私有
    /// 认证三步走的同一张码。参数 [1,0,0] 开、[3,0,0] 收尾。
    static let sonyConnect: UInt16 = 0x9201
    /// 换协议版本。参数 [0x00C8]，返回 2 字节版本号。
    static let sonyExtDeviceInfo: UInt16 = 0x9202
    /// 写一条 SDIO 属性：参数是属性码，data 是值。
    static let setSDIOPropValue: UInt16 = 0x9205
    /// 按键：参数是按钮属性码，data 2=按下 1=松开。
    static let controlDevice: UInt16 = 0x9207
    /// 一次读回全部属性。解析见 SonySDIO。
    static let sonyAllPropData: UInt16 = 0x9209

    /// 取景用的虚拟对象句柄。相机里并不存在这个对象，
    /// 索尼用它把实时取景帧暴露成一个可以反复 GetObject 的对象。
    static let liveViewHandle: UInt32 = 0xFFFF_C002
    /// 拍完的照片也走同一个通道，句柄不同。
    static let capturedImageHandle: UInt32 = 0xFFFF_C001

    // ---- SDIO 属性码（0xD2xx）
    /// 对焦状态：2/3 表示合焦。
    static let propFocusFound: UInt16 = 0xD213
    /// 内存里有没有照片，≥0x8000 表示有。
    static let propObjectInMemory: UInt16 = 0xD215
    /// 实时取景是否就绪，非 0 表示就绪。
    static let propLiveViewStatus: UInt16 = 0xD221
    /// 拍照后是否自动回传。
    static let propPostviewEnable: UInt32 = 0xD25A
    /// 半按 / 全按快门。
    static let propS1Button: UInt32 = 0xD2C1
    static let propS2Button: UInt32 = 0xD2C2
    /// 标准 PTP 的拍摄模式，索尼也认，用来把相机切到「静止影像」。
    static let propStillCaptureMode: UInt32 = 0x5013

    enum ContainerType: UInt16 {
        case command = 1
        case data = 2
        case response = 3
        case event = 4
    }

    static func makeCommand(code: UInt16, transaction: UInt32, params: [UInt32] = []) -> Data {
        var d = Data()
        let length = UInt32(12 + params.count * 4)
        append(&d, length)
        append(&d, ContainerType.command.rawValue)
        append(&d, code)
        append(&d, transaction)
        for p in params { append(&d, p) }
        return d
    }

    private static func append<T: FixedWidthInteger>(_ d: inout Data, _ v: T) {
        var le = v.littleEndian
        withUnsafeBytes(of: &le) { d.append(contentsOf: $0) }
    }

    struct Response {
        let code: UInt16
        let transaction: UInt32
        let params: [UInt32]

        var isOK: Bool { code == 0x2001 }

        var name: String {
            switch code {
            case 0x2001: return "OK"
            case 0x2002: return "GeneralError"
            case 0x2003: return "SessionNotOpen"
            case 0x2004: return "InvalidTransactionID"
            case 0x2005: return "OperationNotSupported"
            case 0x2006: return "ParameterNotSupported"
            case 0x2007: return "IncompleteTransfer"
            case 0x2009: return "InvalidObjectHandle"
            case 0x200C: return "StoreReadOnly"
            case 0x2019: return "DeviceBusy"
            case 0x201D: return "InvalidParameter"
            case 0x201F: return "DeviceBusy"
            default: return String(format: "0x%04X", code)
            }
        }
    }

    // MARK: - 拆包

    private static func u16(_ b: [UInt8], _ o: Int) -> UInt16? {
        guard o + 1 < b.count else { return nil }
        return UInt16(b[o]) | (UInt16(b[o + 1]) << 8)
    }

    private static func u32(_ b: [UInt8], _ o: Int) -> UInt32? {
        guard o + 3 < b.count else { return nil }
        return UInt32(b[o]) | (UInt32(b[o + 1]) << 8)
            | (UInt32(b[o + 2]) << 16) | (UInt32(b[o + 3]) << 24)
    }

    /// 从一段回包里找响应段的返回码。
    static func responseCode(_ data: Data?) -> UInt16? {
        guard let data, data.count >= 8 else { return nil }
        let b = [UInt8](data)
        guard u16(b, 4) == ContainerType.response.rawValue else { return nil }
        return u16(b, 6)
    }

    /// 解析响应容器，同时把参数带出来（GetDeviceInfo 之类需要）。
    static func parseResponse(_ data: Data) -> Response? {
        let b = [UInt8](data)
        guard b.count >= 12 else { return nil }

        var offset = 0
        while offset + 12 <= b.count {
            let segLen = Int(u32(b, offset) ?? 0)
            guard segLen > 0 else { break }
            if u16(b, offset + 4) == ContainerType.response.rawValue {
                var params: [UInt32] = []
                var o = offset + 12
                while o + 3 < b.count, o < offset + segLen, params.count < 8 {
                    params.append(u32(b, o) ?? 0)
                    o += 4
                }
                return Response(code: u16(b, offset + 6) ?? 0,
                                transaction: u32(b, offset + 8) ?? 0,
                                params: params)
            }
            offset += max(segLen, 12)
        }
        return nil
    }

    /// 从回包里取出数据容器的负载。
    ///
    /// 有的回包自带一段 12 字节头，有的直接把裸数据丢回来，所以先看 Type：
    /// 是 data 就按 Length 裁，是 response 就说明这次没有数据。
    static func dataPayload(_ data: Data?) -> Data? {
        guard let data, !data.isEmpty else { return nil }
        let b = [UInt8](data)
        if b.count >= 12 {
            let declared = Int(u32(b, 0) ?? 0)
            let type = u16(b, 4)
            if type == ContainerType.data.rawValue, declared >= 12, declared <= b.count {
                return data.subdata(in: 12..<declared)
            }
            if type == ContainerType.response.rawValue { return nil }
        }
        return data
    }

    /// 从索尼的负载里抠出 JPEG。
    ///
    /// 负载前 4 字节是一个偏移提示，索尼在它之前塞了自己的头；
    /// 但不能完全相信它（不同固件不一致），所以按 SOI(FFD8)…EOI(FFD9) 兜一遍。
    static func jpeg(in data: Data) -> Data? {
        let b = [UInt8](data)
        guard b.count >= 4 else { return nil }

        let hint = Int(u32(b, 0) ?? 0)
        var start = findSOI(b, from: (hint > 0 && hint < b.count - 1) ? hint : 0)
        if start == nil, hint > 0 { start = findSOI(b, from: 0) }
        guard let soi = start else { return nil }

        var end = b.count
        if b.count >= soi + 4 {
            var i = b.count - 2
            while i > soi + 1 {
                if b[i] == 0xFF && b[i + 1] == 0xD9 {
                    end = i + 2
                    break
                }
                i -= 1
            }
        }
        return data.subdata(in: soi..<end)
    }

    private static func findSOI(_ b: [UInt8], from: Int) -> Int? {
        guard from >= 0, from < b.count - 1 else { return nil }
        for i in from..<(b.count - 1) where b[i] == 0xFF && b[i + 1] == 0xD8 {
            return i
        }
        return nil
    }
}
