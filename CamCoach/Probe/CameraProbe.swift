// SPDX-License-Identifier: Apache-2.0
import Foundation
import ImageCaptureCore

struct ProbeLog: Identifiable {
    enum Level {
        case info, ok, fail, warn
    }

    let id = UUID()
    let level: Level
    let text: String
    let detail: String?

    var icon: String {
        switch level {
        case .info: return "circle.dotted"
        case .ok: return "checkmark.circle.fill"
        case .fail: return "xmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        }
    }
}

/// 相机探针。
///
/// 设计原则：**只观察，不假设**。
///
/// 这里的 Sony 私有命令码全部来自社区逆向，没有官方文档背书。所以每一步
/// 都只做一件事——发出去，把返回码原样记下来。某个码写错了会看到
/// OperationNotSupported，那本身就是有用的信息；如果按「正确流程」写死
/// 一串 then 链，第一个错误就会把后面全挡住，反而什么都测不出来。
///
/// 写属性、拉取景这类会改动相机状态的操作单独做成按钮，默认不执行。
final class CameraProbe: NSObject, ObservableObject {

    @Published private(set) var logs: [ProbeLog] = []
    @Published private(set) var running = false
    @Published private(set) var phase = "未开始"
    @Published private(set) var deviceLabel = "未发现设备"

    private let browser = ICDeviceBrowser()
    private var camera: ICCameraDevice?
    private var txn: UInt32 = 0
    private var found = false

    override init() {
        super.init()
        browser.delegate = self
        browser.browsedDeviceTypes = [.camera]
    }

    // MARK: - 对外接口

    func begin() {
        guard !running else { return }
        main {
            self.running = true
            self.logs.removeAll()
            self.phase = "搜索设备"
            self.deviceLabel = "搜索中…"
            self.found = false
        }
        log(.info, "开始搜索 USB 设备")

        browser.stop()
        browser.start()

        Task {
            var waited = 0.0
            while waited < 6.0 {
                if self.found { break }
                try? await Task.sleep(nanoseconds: 300_000_000)
                waited += 0.3
            }
            guard let cam = self.camera else {
                self.log(.fail, "6 秒内没有发现相机", detail: """
                三个最常见的原因，按顺序查：
                ① 相机不在「遥控拍摄」模式（USB 连接方式要选「遥控拍摄」，屏幕会显示 -PC-）
                ② 用的是充电线，不是数据线
                ③ 系统弹窗问「允许访问相机」时点了拒绝
                """)
                self.finish("没有设备")
                return
            }
            await self.runProbe(on: cam)
        }
    }

    /// 复制成纯文本，方便贴出来。
    var reportText: String {
        var out = "CamCoach 探针报告\n设备：\(deviceLabel)\n\n"
        for l in logs {
            let tag: String
            switch l.level {
            case .info: tag = "[·]"
            case .ok: tag = "[OK]"
            case .fail: tag = "[X]"
            case .warn: tag = "[!]"
            }
            out += "\(tag) \(l.text)\n"
            if let d = l.detail, !d.isEmpty {
                for line in d.split(separator: "\n") {
                    out += "      \(line)\n"
                }
            }
        }
        return out
    }

    // MARK: - 主流程

    private func runProbe(on cam: ICCameraDevice) async {
        log(.ok, "发现相机：\(cam.name ?? "未命名")", detail: description(of: cam))

        main { self.phase = "打开会话" }

        log(.info, "请求打开 PTP 会话")
        cam.requestOpenSession()

        // 不用 delegate 等回调，直接给一点时间。会话没开成的话，
        // 后面第一条命令会回 SessionNotOpen —— 那也是我们要观察的结果之一。
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        log(.info, "等待 1.5 秒后开始发命令")

        // ---- 1. 标准 PTP：能不能读设备信息
        main { self.phase = "标准 PTP" }
        log(.info, "GetDeviceInfo (0x1001)")
        if let r = await send(0x1001, [], "GetDeviceInfo") {
            if r.isOK {
                log(.ok, "标准 PTP 通道可用", detail: "返回参数 \(r.params.map { String(format: "0x%08X", $0) }.joined(separator: ", "))")
            } else {
                log(.warn, "GetDeviceInfo 返回 \(r.name)", detail: "通道可能在但会话没开好，继续往下测")
            }
        }

        // ---- 2. Sony 握手（四步，逐步记录）
        main { self.phase = "Sony 握手" }

        await step(PTP.sonyConnect, [1], "SDIOConnect(1)")
        await step(PTP.sonyConnect, [2], "SDIOConnect(2)")
        await step(PTP.sonyExtDeviceInfo, [], "SDIOGetExtDeviceInfo")
        await step(PTP.sonyConnect, [3], "SDIOConnect(3)")

        // ---- 3. 读属性
        main { self.phase = "读参数" }

        if let r = await send(PTP.sonyAllPropData, [], "SDIOGetAllDevicePropData") {
            if r.isOK {
                log(.ok, "能读全部属性（0x9209）")
            } else {
                log(.warn, "读全部属性返回 \(r.name)")
            }
        }

        // 单独读几个关键参数，看描述符能不能拿到
        for (code, name) in [
            (PTP.propISO, "ISO"),
            (PTP.propShutterSpeed, "快门"),
            (PTP.propFNumber, "光圈"),
            (PTP.propExposureProgram, "曝光模式"),
        ] {
            if let r = await send(PTP.getDevicePropValue, [code], "GetDevicePropValue \(name)") {
                if r.isOK {
                    let v = r.params.first.map { String($0) } ?? "?"
                    log(.ok, "\(name) 可读，当前值 \(v)")
                } else {
                    log(.warn, "\(name) 读不到：\(r.name)")
                }
            }
        }

        finish("完成")
    }

    private func step(_ code: UInt16, _ params: [UInt32], _ label: String) async {
        guard let r = await send(code, params, label) else { return }
        let p = params.map { String(format: "0x%X", $0) }.joined(separator: ",")
        if r.isOK {
            log(.ok, "\(label) → OK", detail: p.isEmpty ? nil : "参数 \(p)")
        } else if r.code == 0x2005 || r.code == 0x2019 {
            log(.warn, "\(label) → \(r.name)", detail: "这条不支持，说明命令码或参数和这台机器对不上")
        } else {
            log(.warn, "\(label) → \(r.name)", detail: p.isEmpty ? nil : "参数 \(p)")
        }
    }

    // MARK: - 发一条 PTP

    private func send(_ code: UInt16, _ params: [UInt32], _ label: String) async -> PTP.Response? {
        guard let cam = camera else { return nil }
        txn += 1
        let cmd = PTP.makeCommand(code: code, transaction: txn, params: params)

        let raw: Data? = await withCheckedContinuation { cont in
            cam.requestSendPTPCommand(
                cmd,
                outData: nil,
                sendInstruction: true,
                receiveYieldData: false
            ) { resp, _, err in
                if let err = err {
                    self.log(.fail, "\(label) 发送失败", detail: err.localizedDescription)
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: resp)
            }
        }

        guard let raw = raw else { return nil }
        guard let parsed = PTP.parseResponse(raw) else {
            log(.warn, "\(label) 回了 \(raw.count) 字节，但不是标准响应容器",
                detail: "前 16 字节：" + raw.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " "))
            return nil
        }
        return parsed
    }

    // MARK: - 小工具

    private func description(of cam: ICCameraDevice) -> String {
        // 只用确定存在的属性。productKind / transportType 的类型在
        // 不同 SDK 版本里可选性不一样，写死 if let 反而可能编不过。
        var lines: [String] = []
        lines.append("会话已开：\(cam.hasOpenSession ? "是" : "否")")
        lines.append("访问受限：\(cam.isAccessRestricted ? "是" : "否")")
        return lines.joined(separator: "\n")
    }

    private func log(_ level: ProbeLog.Level, _ text: String, detail: String? = nil) {
        main { self.logs.append(ProbeLog(level: level, text: text, detail: detail)) }
    }

    private func finish(_ p: String) {
        main {
            self.running = false
            self.phase = p
        }
    }

    private func main(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }
}

// MARK: - 设备枚举

extension CameraProbe: ICDeviceBrowserDelegate {

    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard let cam = device as? ICCameraDevice else { return }
        cam.delegate = self
        camera = cam
        found = true
        main { self.deviceLabel = cam.name ?? "相机" }
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        guard let cam = device as? ICCameraDevice, cam == camera else { return }
        camera = nil
        main { self.deviceLabel = "设备已断开" }
        log(.warn, "相机断开了")
    }
}

extension CameraProbe: ICCameraDeviceDelegate {

    // ---- ICDeviceDelegate 的 required 三件套。
    // ObjC 协议里这几个没标 @optional，Swift 少一个就报
    // "type does not conform to protocol"，而且报错位置指向类型声明，
    // 不指到具体缺哪个，得往上翻 note 才知道。

    func didRemoveDevice(_ device: ICDevice) {
        guard let cam = device as? ICCameraDevice, cam == camera else { return }
        camera = nil
        main { self.deviceLabel = "设备已移除" }
    }

    func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
        if let error = error {
            log(.fail, "打开会话失败", detail: error.localizedDescription)
        } else {
            log(.ok, "PTP 会话已打开")
        }
    }

    func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {
        if let error = error {
            log(.warn, "关闭会话时报错", detail: error.localizedDescription)
        }
    }

    // ---- ICCameraDeviceDelegate 的 required 两个。
    // 我们不下载缩略图和元数据（这一版只问参数），但协议要求必须实现，
    // 空着即可。

    func cameraDevice(
        _ camera: ICCameraDevice,
        didReceiveThumbnail thumbnail: CGImage?,
        for item: ICCameraItem,
        error: Error?
    ) {}

    func cameraDevice(
        _ camera: ICCameraDevice,
        didReceiveMetadata metadata: [AnyHashable: Any]?,
        for item: ICCameraItem,
        error: Error?
    ) {}

    // ---- 以下是 optional，实现了就能多看到点东西

    func cameraDevice(_ camera: ICCameraDevice, didReceiveOpenSessionError error: Error?) {
        if let error = error {
            log(.fail, "相机会话打开出错", detail: error.localizedDescription)
        }
    }

    func cameraDeviceDidBecomeReady(withCompleteContentCatalog camera: ICCameraDevice) {
        log(.info, "相机会话就绪")
    }

    func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent data: Data) {
        log(.info, "收到 PTP 事件 \(data.count) 字节",
            detail: data.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " "))
    }
}
