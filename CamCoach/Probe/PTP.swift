// SPDX-License-Identifier: Apache-2.0
import Foundation

/// PTP（ISO 15740）的容器封装。
///
/// 相机端的每个包都是同一套结构：
///   Length(4) + Type(2) + Code(2) + TransactionID(4) + Params(4×N)
/// 全部小端。Length 算的是整个容器，不是 payload。
///
/// 这里的 Sony 私有命令码来自社区逆向（libgphoto2 / 各路 PTP 抓包），
/// 不是官方文档。所以探针的做法是「发出去、记返回码」，而不是假定它一定对——
/// 如果某个码写错了，我们会看到 OperationNotSupported，而不是崩溃。
enum PTP {

    // ---- 标准 PTP
    static let getDeviceInfo: UInt16 = 0x1001
    static let openSession: UInt16 = 0x1002
    static let closeSession: UInt16 = 0x1003
    static let getDevicePropDesc: UInt16 = 0x1015
    static let getDevicePropValue: UInt16 = 0x1015
    static let setDevicePropValue: UInt16 = 0x1016

    // ---- Sony 私有
    static let sonyConnect: UInt16 = 0x9201
    static let sonyExtDeviceInfo: UInt16 = 0x9202
    static let sonyControl: UInt16 = 0x9207
    static let sonyAllPropData: UInt16 = 0x9209

    /// 取景/预览走的虚拟对象句柄。这是个「不存在的对象」，Sony 用它
    /// 把实时取景帧当成一个可以反复读的对象。
    static let viewfinderHandle: UInt32 = 0xFFFF_C002

    // 几个要探测的属性码（标准 PTP DevicePropCode）
    static let propISO: UInt32 = 0x500F
    static let propShutterSpeed: UInt32 = 0x500D
    static let propFNumber: UInt32 = 0x5007
    static let propExposureProgram: UInt32 = 0x500E

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

    static func makeData(code: UInt16, transaction: UInt32, payload: Data) -> Data {
        var d = Data()
        let length = UInt32(12 + payload.count)
        append(&d, length)
        append(&d, ContainerType.data.rawValue)
        append(&d, code)
        append(&d, transaction)
        d.append(payload)
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
            case 0x2009: return "InvalidStorageID"
            case 0x200C: return "StoreReadOnly"
            case 0x2019: return "DevicePropNotSupported"
            case 0x201D: return "InvalidParameter"
            case 0x201F: return "DeviceBusy"
            default: return String(format: "0x%04X", code)
            }
        }
    }

    /// 解析响应容器。相机回的可能是响应包，也可能带一个数据包在前面，
    /// 所以这里扫一遍找 type=3 的那一段，而不是死认前 12 字节。
    static func parseResponse(_ data: Data) -> Response? {
        let bytes = [UInt8](data)
        guard bytes.count >= 12 else { return nil }

        func u16(_ o: Int) -> UInt16 {
            guard o + 1 < bytes.count else { return 0 }
            return UInt16(bytes[o]) | (UInt16(bytes[o + 1]) << 8)
        }
        func u32(_ o: Int) -> UInt32 {
            guard o + 3 < bytes.count else { return 0 }
            return UInt32(bytes[o])
                | (UInt32(bytes[o + 1]) << 8)
                | (UInt32(bytes[o + 2]) << 16)
                | (UInt32(bytes[o + 3]) << 24)
        }

        // 正常情况第一段就是响应
        if u16(4) == ContainerType.response.rawValue {
            var params: [UInt32] = []
            var o = 12
            while o + 3 < bytes.count && params.count < 5 {
                params.append(u32(o))
                o += 4
            }
            return Response(code: u16(6), transaction: u32(8), params: params)
        }

        // 否则按 Length 逐段跳，找响应段
        var offset = 0
        while offset + 12 <= bytes.count {
            let segLen = Int(u32(offset))
            if segLen <= 0 { break }
            if u16(offset + 4) == ContainerType.response.rawValue {
                var params: [UInt32] = []
                var o = offset + 12
                while o + 3 < bytes.count && o < offset + segLen && params.count < 5 {
                    params.append(u32(o))
                    o += 4
                }
                return Response(code: u16(offset + 6), transaction: u32(offset + 8), params: params)
            }
            offset += segLen
        }
        return nil
    }
}
