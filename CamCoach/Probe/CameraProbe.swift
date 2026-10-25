// SPDX-License-Identifier: Apache-2.0
import Foundation
import ImageCaptureCore
import UIKit

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
    /// 探针抓到的第一帧取景，用来证明这条链路真的能出画面。
    @Published private(set) var previewFrame: UIImage?

    private let browser = ICDeviceBrowser()
    private var camera: ICCameraDevice?
    private var found = false

    override init() {
        super.init()
        browser.delegate = self
        // 不设 browsedDeviceTypes：iOS 上这个成员不存在（macOS 才有），
        // 默认就会枚举相机，够了。
    }

    // MARK: - 对外接口

    func begin() {
        guard !running else { return }
        main {
            self.running = true
            self.logs.removeAll()
            self.phase = "搜索设备"
            self.deviceLabel = "搜索中…"
            self.previewFrame = nil
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

    /// 探针要做的事只有一件：回答「这台相机在 iPhone 上能不能出画面」。
    ///
    /// 所以它不逐条试命令，而是把整条取景链路一次走到底，
    /// 每一步的返回码都记下来。哪一步断了，报告里直接看得出来。
    private func runProbe(on cam: ICCameraDevice) async {
        log(.ok, "发现相机：\(cam.name ?? "未命名")", detail: description(of: cam))

        main { self.phase = "打开会话" }
        do {
            try await cam.requestOpenSession()
        } catch {
            log(.warn, "打开会话报错，继续试命令", detail: error.localizedDescription
                + "\n有时会话已经开了，只是系统报了个警告")
        }
        try? await Task.sleep(nanoseconds: 1_200_000_000)

        // PTP 发包要阻塞等回调，得挪到专门的后台队列，
        // 别占 Swift 并发的线程池，也别碰主线程。
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                self.probeLink(on: cam)
                cont.resume()
            }
        }
    }

    private func probeLink(on cam: ICCameraDevice) {
        let session = SonyPtpSession(camera: cam)

        // ---- 1. 标准 PTP 通道
        main { self.phase = "标准 PTP" }
        do {
            // 认证前先撞一次，看这条通道本身通不通。
            _ = try session.readProperties()
        } catch {
            log(.info, "认证前读属性不通，符合预期")
        }

        // ---- 2. 索尼认证
        main { self.phase = "索尼认证" }
        do {
            let ver = try session.authenticate()
            log(.ok, "认证通过", detail: "相机声明 PTP 协议版本 "
                + String(format: "0x%04X", ver))
        } catch {
            log(.fail, "认证失败：\(error.localizedDescription)", detail: """
            四步顺序是 0x9201[1,0,0] → 0x9201[2,0,0] → 0x9202[0xC8] → 0x9201[3,0,0]。
            卡在 0x9201[1] 一般说明相机不在遥控模式；
            卡在 0x9202 一般说明固件不认这个协议版本。
            认证不过，后面一切都读不到，这里就停。
            """)
            finish("认证未通过")
            return
        }

        // ---- 3. 读全部属性
        main { self.phase = "读属性" }
        var props: [SonySDIO.Property] = []
        do {
            props = try session.readProperties()
            log(.ok, "读回 \(props.count) 条属性")
        } catch {
            log(.fail, "读属性失败：\(error.localizedDescription)")
            finish("属性读不到")
            return
        }

        let sdio = props.filter { $0.code >= 0xD000 }
        log(.info, "其中索尼私有属性 \(sdio.count) 条",
            detail: sdio.prefix(60).map { p in
                p.label + (p.enabled ? "" : "(当前无效)") + (p.writable ? "可写" : "")
            }.joined(separator: " "))

        for (code, name) in [(PTP.propLiveViewStatus, "取景状态 D221"),
                             (PTP.propObjectInMemory, "内存图像 D215"),
                             (PTP.propFocusFound, "对焦状态 D213")] {
            if let v = SonySDIO.scalar(props, code) {
                log(.ok, "\(name) 可读，当前 \(v)")
            } else {
                log(.warn, "\(name) 没出现", detail: "这条是取景/拍摄必需的状态位")
            }
        }

        // ---- 4. 等取景就绪
        main { self.phase = "等取景就绪" }
        let t0 = Date()
        do {
            try session.waitForLiveView { round, status in
                if round % 10 == 0 {
                    let s = status.map { "\($0)" } ?? "读不到"
                    self.log(.info, "第 \(round) 次轮询，D221 = \(s)")
                }
            }
            let dt = Date().timeIntervalSince(t0)
            log(.ok, "取景就绪", detail: String(format: "等了 %.1f 秒", dt))
        } catch {
            log(.fail, "取景没就绪", detail: error.localizedDescription)
            finish("取景未就绪")
            return
        }

        // ---- 5. 抓一帧
        main { self.phase = "抓取景帧" }
        do {
            guard let jpeg = try session.liveViewFrame() else {
                log(.warn, "就绪了但这一帧是空的", detail: "再抓一次通常就有了，可以重跑探针")
                finish("取到空帧")
                return
            }
            let image = UIImage(data: jpeg)
            let size = image.map { "\(Int($0.size.width))×\(Int($0.size.height))" } ?? "解不出来"
            main { self.previewFrame = image }
            log(.ok, "取到一帧取景", detail: "\(jpeg.count) 字节，\(size)")
            if image == nil {
                log(.warn, "JPEG 有内容但解不出图",
                    detail: "前 8 字节：" + jpeg.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " "))
            }
        } catch {
            log(.fail, "抓帧失败：\(error.localizedDescription)")
            finish("抓帧失败")
            return
        }

        finish("链路全通")
        log(.ok, "这条路走通了：实时取景能在 iPhone 上出画面", detail: """
        下一步就是在这条通道上做两件事：
        ① 连续抓帧，做成取景画面
        ② 一边抓帧一边读 D2xx 属性，把参数显示出来
        """)
    }

    // MARK: - 小工具

    private func description(of cam: ICCameraDevice) -> String {
        // 只用确定存在的属性。productKind / transportType / isAccessRestricted
        // 这几个在 iOS 上不一定有（有些是 macOS 专属），写上去反而编不过。
        var lines: [String] = []
        lines.append("会话已开：\(cam.hasOpenSession ? "是" : "否")")
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

    func didRemove(_ device: ICDevice) {
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

    // ---- ICCameraDeviceDelegate 里另外几个 required 方法。
    // 这些在 ObjC 头文件里都没标 @optional，Swift 少一个就整个协议不通过。
    // 我们暂时不关心内容目录的变化（这一版只问参数，不读照片），
    // 所以留空——但方法必须存在。

    func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {}
    func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {}
    func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}
    func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}

    func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {
        log(.warn, "设备访问被限制", detail: "可能是 iOS 的隐私限制，需要在系统设置里允许")
    }

    func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {
        log(.ok, "设备访问限制已解除")
    }

    func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        log(.info, "相机会话就绪")
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

    func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent data: Data) {
        log(.info, "收到 PTP 事件 \(data.count) 字节",
            detail: data.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " "))
    }
}
