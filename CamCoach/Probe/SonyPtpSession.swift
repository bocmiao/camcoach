// SPDX-License-Identifier: Apache-2.0
import Foundation
import ImageCaptureCore

/// 与索尼机身的一条 PTP 会话。
///
/// 链路顺序是固定的，少一步后面就全废：
///   1. 打开 PTP 会话（ImageCaptureCore 的 requestOpenSession）
///   2. 索尼认证 0x9201[1] → 0x9201[2] → 0x9202[0xC8] → 0x9201[3]
///   3. 0x9209 一次读回全部属性（含 D221：取景是否就绪）
///   4. 0x1008 查对象信息 → 0x1009 取对象，句柄 0xFFFFC002 是实时取景
///
/// 认证那四步的参数必须是 `[1,0,0]` / `[2,0,0]` / `[0x00C8]` / `[3,0,0]`。
/// 只传 `[1]`、`[2]` 这类单参数是发不通的，相机只会回一个通用错误，
/// 看起来像「命令码写错了」，实际是参数个数不对。
///
/// 这里的 send 是**同步阻塞**的（用信号量等 ImageCaptureCore 回调），
/// 所以只能在后台线程调用，不要放在主线程上。
final class SonyPtpSession {

    /// 相机回的业务错误。带上操作码，方便对着日志查是哪一步。
    struct PTPError: LocalizedError {
        let operation: UInt16
        let code: UInt16
        let retryable: Bool

        var errorDescription: String? {
            "0x\(String(format: "%04X", operation)) 返回 \(PTP.Response(code: code, transaction: 0, params: []).name)"
                + String(format: "（0x%04X）", code)
        }
    }

    struct TimeoutError: LocalizedError {
        var errorDescription: String? { "PTP 命令 5 秒没回，通道可能被系统相机接管了" }
    }

    /// 一次取景就绪需要等多久。相机切到 PC 遥控状态本身要几秒。
    private static let authRetries = 6
    private static let liveViewPolls = 50

    private let camera: ICCameraDevice
    private var txn: UInt32 = 0

    /// 认证用的协议版本，相机在 0x9202 里回。见 `authenticate()` 返回值。
    private(set) var protocolVersion: UInt16 = 0

    init(camera: ICCameraDevice) {
        self.camera = camera
    }

    // MARK: - 认证

    /// 走完索尼的四步认证。返回相机声明支持的 PTP 协议版本（通常是 0x00C8）。
    @discardableResult
    func authenticate() throws -> UInt16 {
        _ = try send(PTP.sonyConnect, params: [1, 0, 0], expectsData: true)

        // 第二步可能回 DeviceBusy，相机还在切模式。给几次机会。
        var lastError: Error?
        for _ in 0..<3 {
            do {
                _ = try send(PTP.sonyConnect, params: [2, 0, 0], expectsData: true)
                lastError = nil
                break
            } catch {
                lastError = error
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
        if let lastError { throw lastError }

        var versionData: Data?
        for _ in 0..<Self.authRetries {
            let r = try send(PTP.sonyExtDeviceInfo, params: [0x00C8],
                             expectsData: true, allowBusy: true)
            if let d = r.data, d.count >= 2 {
                versionData = d
                break
            }
            Thread.sleep(forTimeInterval: 0.15)
        }
        guard let d = versionData, d.count >= 2 else {
            throw PTPError(operation: PTP.sonyExtDeviceInfo, code: 0x2002, retryable: true)
        }
        protocolVersion = UInt16(d[d.startIndex]) | (UInt16(d[d.startIndex + 1]) << 8)
        guard protocolVersion >= 0x00C8 else {
            throw PTPError(operation: PTP.sonyExtDeviceInfo, code: protocolVersion,
                           retryable: false)
        }

        _ = try send(PTP.sonyConnect, params: [3, 0, 0], expectsData: true)
        return protocolVersion
    }

    // MARK: - 属性

    /// 读回全部属性。轮询 D221/D215/D213 时也走这条。
    func readProperties() throws -> [SonySDIO.Property] {
        let r = try send(PTP.sonyAllPropData, expectsData: true, allowBusy: true)
        guard let d = r.data else { return [] }
        return SonySDIO.parseAll(d)
    }

    // MARK: - 实时取景

    /// 等取景就绪。D221 非 0 表示相机已经把取景对象挂出来了。
    ///
    /// 就绪瞬间 `0x1008` 可能还是 InvalidHandle，所以这里既看 D221 也试一次句柄。
    func waitForLiveView(progress: ((Int, Int64?) -> Void)? = nil) throws {
        var last: Int64?
        for i in 0..<Self.liveViewPolls {
            let props = try readProperties()
            last = SonySDIO.scalar(props, PTP.propLiveViewStatus)
            progress?(i, last)
            if let last, last != 0 {
                do {
                    _ = try send(PTP.getObjectInfo, params: [PTP.liveViewHandle],
                                 expectsData: true)
                    return
                } catch let e as PTPError where e.retryable {
                    // D221 刚就绪、对象还没挂出来，再等一轮。
                }
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw LiveViewError.notReady(last)
    }

    struct LiveViewError: LocalizedError {
        let status: Int64?
        var errorDescription: String? {
            let s = status.map { String(format: "0x%04X", $0) } ?? "读不到"
            return "取景没就绪（D221 = \(s)）。相机 USB 连接方式要选「电脑遥控」，"
                + "并且停在拍摄画面，不能停在菜单里"
        }
    }

    /// 取一帧实时取景。返回 JPEG 原始数据，不是解码后的图。
    func liveViewFrame() throws -> Data? {
        let info = try send(PTP.getObjectInfo, params: [PTP.liveViewHandle],
                            expectsData: true,
                            accepted: [0x2001, 0x2009, 0x2019])
        if info.code != 0x2001 { return nil }

        let obj = try send(PTP.getObject, params: [PTP.liveViewHandle],
                           expectsData: true, accepted: [0x2001, 0x200F])
        if obj.code == 0x200F { return nil }
        guard let data = obj.data else { return nil }
        return PTP.jpeg(in: data)
    }

    // MARK: - 拍摄

    /// 半按 → 全按 →（等对焦）→ 松手。松手放在 defer 里，任何异常都不会把快门卡住。
    func captureStill() throws {
        try setButton(PTP.propS1Button, down: true)
        Thread.sleep(forTimeInterval: 0.09)
        try setButton(PTP.propS2Button, down: true)
        defer {
            try? setButton(PTP.propS2Button, down: false)
            try? setButton(PTP.propS1Button, down: false)
        }

        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline {
            let f = SonySDIO.scalar(try readProperties(), PTP.propFocusFound)
            if f == 2 || f == 3 { break }     // 2 = 合焦, 3 = 合焦（AF-S 锁定）
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    /// 拍完从相机取回 JPEG。D215 要 ≥ 0x8000 才说明图像已经在内存里。
    func pollCapturedJPEG(timeout: TimeInterval = 4) throws -> Data? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let mem = SonySDIO.scalar(try readProperties(), PTP.propObjectInMemory)
            if let mem, mem >= 0x8000 {
                let info = try send(PTP.getObjectInfo, params: [PTP.capturedImageHandle],
                                    expectsData: true, accepted: [0x2001, 0x2009, 0x2019])
                if info.code == 0x2001 {
                    let obj = try send(PTP.getObject, params: [PTP.capturedImageHandle],
                                       expectsData: true, accepted: [0x2001, 0x2009, 0x2019])
                    if obj.code == 0x2001, let d = obj.data, let jpeg = PTP.jpeg(in: d) {
                        return jpeg
                    }
                }
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return nil
    }

    private func setButton(_ code: UInt32, down: Bool) throws {
        _ = try send(PTP.controlDevice, params: [code],
                     outgoing: Data([down ? 2 : 1]), expectsData: false)
    }

    // MARK: - 收发包

    struct Reply {
        let code: UInt16
        let data: Data?
    }

    private func send(_ op: UInt16, params: [UInt32] = [], outgoing: Data? = nil,
                      expectsData: Bool = false, allowBusy: Bool = false,
                      accepted: Set<UInt16> = [0x2001]) throws -> Reply {
        txn &+= 1
        let command = PTP.makeCommand(code: op, transaction: txn, params: params)

        // ImageCaptureCore 的回调在别的线程上，信号量是这块唯一能用的同步手段。
        let sem = DispatchSemaphore(value: 0)
        var responseData: Data?
        var ptpData: Data?
        var failure: Error?

        camera.requestSendPTPCommand(command, outData: outgoing) { a, b, e in
            responseData = a
            ptpData = b
            failure = e
            sem.signal()
        }
        guard sem.wait(timeout: .now() + 5) == .success else {
            throw TimeoutError()
        }
        if let failure {
            // 系统层报错（没权限、设备被拔、被系统相机接管）也往上抛，
            // 由探针决定要不要继续试下一条。
            throw NSError(domain: "CamCoach.PTP", code: Int(op), userInfo: [
                NSLocalizedDescriptionKey: "0x\(String(format: "%04X", op)) 系统层失败：\(failure.localizedDescription)",
            ])
        }

        let code = PTP.responseCode(responseData) ?? PTP.responseCode(ptpData) ?? 0x2001
        let ok = accepted.contains(code) || (allowBusy && code == 0x2019)
        guard ok else {
            let retryable = [UInt16(0x2019), 0x200F, 0x2009].contains(code)
            throw PTPError(operation: op, code: code, retryable: retryable)
        }
        let payload = expectsData ? (PTP.dataPayload(responseData) ?? PTP.dataPayload(ptpData)) : nil
        return Reply(code: code, data: payload)
    }
}
