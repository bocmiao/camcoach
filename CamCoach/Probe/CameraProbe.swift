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
    /// 记录时间。连续两次探测的间隔、超时发生在第几秒，全靠它看。
    let at: Date

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

    // ---- 自检要显示的分层证据。找不到相机时，这几个值就是全部线索。
    @Published private(set) var contentsAuth = "未查询"
    @Published private(set) var controlAuth = "未查询"
    @Published private(set) var browseMask = "未设置"
    @Published private(set) var browsingNow = false
    @Published private(set) var enumeratedCount = 0
    /// didAdd 回调次数。它大于 0 而 enumeratedCount 是 0，说明设备进来又被判定为非相机。
    @Published private(set) var addCount = 0
    /// 每次 didAdd 的原始描述，原样留着，不加工。
    @Published private(set) var rawDevices: [String] = []

    /// 每次扫描换一个新的浏览器实例，这里不能是 let。
    /// 复用同一个实例做 stop()→start()，第二次往往一台设备都枚举不到。
    private var browser = ICDeviceBrowser()
    private var camera: ICCameraDevice?
    /// 探测次数。日志不再每次清空，靠这个编号把多轮记录分开。
    private var attempts = 0

    override init() {
        super.init()
        browser.delegate = self
    }

    // MARK: - 对外接口

    func begin() {
        guard !running else { return }
        attempts += 1
        let n = attempts
        main {
            self.running = true
            self.phase = "申请授权"
            self.deviceLabel = "搜索中…"
            self.previewFrame = nil
            self.camera = nil
            self.addCount = 0
            self.enumeratedCount = 0
            self.rawDevices.removeAll()
        }
        // 日志不清空。第一次成功、第二次失败这种对照，只有把两轮放在一份报告里才看得出来。
        log(.info, "──── 第 \(n) 次探测 ────")
        Task { await self.scan() }
    }

    // MARK: - 找到设备

    /// 从授权一路走到找到设备，每一级都留证据。
    ///
    /// 顺序不能换。没授权时系统会静默不枚举，后面看到的全是假失败，
    /// 排查时就会一路往协议层找，方向从一开始就是错的。
    private func scan() async {
        // 换一个新的浏览器实例再扫。
        //
        // 上一版是复用同一个实例 stop()→start()，结果第一次能连、第二次一台都枚举不到：
        // 同一个 ICDeviceBrowser 重启浏览时，不会把「已经报过」的设备重新报一遍
        // didAdd，devices 也可能被清空。加上第一次开过 PTP 会话没关，
        // 相机在系统侧仍算「被占用」，就彻底看不见了。
        await replaceBrowser()

        await requestAuthorizations()

        // 启停必须回主线程。ICDeviceBrowser 靠发起线程的 runloop 派发回调，
        // 在没有 runloop 的后台线程上调 start()，didAdd 永远不会来——
        // 现象和「没插相机」一模一样。
        await MainActor.run {
            self.phase = "搜索设备"
            // iOS 15.2 起才有的属性，默认值不一定含本地 USB。
            // 显式指定「相机 + 本地连接」——少这一句，可能一台设备都枚举不到。
            // init(rawValue:) 是可失败的（组合位不一定落在合法取值里），退回 .camera。
            let mask = ICDeviceTypeMask(
                rawValue: ICDeviceTypeMask.camera.rawValue
                    | ICDeviceLocationTypeMask.local.rawValue) ?? .camera
            self.browser.browsedDeviceTypeMask = mask
            self.browseMask = "相机 + 本地连接"
            self.browser.start()
        }
        log(.info, "浏览器已启动", detail: "isBrowsing = \(browser.isBrowsing)\n过滤条件：相机 + 本地连接")

        // 设备有可能已经在浏览器里、但 didAdd 不会再报一次，先直接捡现成的。
        if let known = liveDevices().first {
            adopt(known, source: "启动时已在浏览器的设备列表里")
        }

        // 20 秒。相机切到遥控模式会重连一次 USB，插上就点开始的话前几秒是空的。
        let deadline = Date().addingTimeInterval(20)
        var lastCount = -1
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 500_000_000)
            let count = browser.devices?.count ?? 0
            main {
                self.enumeratedCount = count
                self.browsingNow = self.browser.isBrowsing
            }
            if count != lastCount {
                lastCount = count
                log(.info, "系统枚举到 \(count) 台设备")
            }
            if camera == nil, let known = liveDevices().first {
                adopt(known, source: "扫描过程中出现在设备列表里")
            }
            if let cam = camera {
                await runProbe(on: cam)
                return
            }
        }
        diagnoseNoDevice()
        finish("没有设备")
    }

    /// 丢掉旧浏览器，换一个新的。给系统相机守护进程一点时间释放上一轮的占用。
    private func replaceBrowser() async {
        browser.delegate = nil
        browser.stop()
        try? await Task.sleep(nanoseconds: 400_000_000)

        let fresh = ICDeviceBrowser()
        fresh.delegate = self
        browser = fresh
    }

    private func liveDevices() -> [ICCameraDevice] {
        (browser.devices ?? []).compactMap { $0 as? ICCameraDevice }
    }

    private func adopt(_ cam: ICCameraDevice, source: String) {
        guard camera !== cam else { return }
        cam.delegate = self
        camera = cam
        main { self.deviceLabel = cam.name ?? "相机" }
        log(.ok, "已接管相机", detail: "来源：\(source)\n名称：\(cam.name ?? "未报告")\n"
            + "能力：\(cam.capabilities.isEmpty ? "未报告" : cam.capabilities.joined(separator: " "))")
    }

    private func requestAuthorizations() async {
        log(.info, "访问权限（询问前）", detail: "内容：\(Self.authLabel(browser.contentsAuthorizationStatus))"
            + "／控制：\(Self.authLabel(browser.controlAuthorizationStatus))")

        // 回调可能一直不来（框架没准备好）。等 8 秒没消息就读当前状态往下走，
        // 不能让探针永远停在「申请授权」。
        let contents = await withCheckedContinuation { (c: CheckedContinuation<ICAuthorizationStatus, Never>) in
            let once = ResumeOnce(c)
            DispatchQueue.main.async {
                self.browser.requestContentsAuthorization { st in once.resume(st) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                once.resume(self.browser.contentsAuthorizationStatus)
            }
        }
        main { self.contentsAuth = Self.authLabel(contents) }

        let control = await withCheckedContinuation { (c: CheckedContinuation<ICAuthorizationStatus, Never>) in
            let once = ResumeOnce(c)
            DispatchQueue.main.async {
                self.browser.requestControlAuthorization { st in once.resume(st) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                once.resume(self.browser.controlAuthorizationStatus)
            }
        }
        main { self.controlAuth = Self.authLabel(control) }

        if Self.isAuthorized(contents) && Self.isAuthorized(control) {
            log(.ok, "已拿到相机访问授权")
        } else {
            log(.warn, "授权不全，系统可能直接不枚举设备",
                detail: "内容：\(Self.authLabel(contents))／控制：\(Self.authLabel(control))\n"
                    + "去 iOS 设置 → 取景助手，把「照片」和「相机」都打开，再回来重新点开始。")
        }
    }

    /// `ICAuthorizationStatus` 是字符串枚举（不是整数），所以按成员比较，
    /// 不去猜 rawValue 的实际字面值。
    static func authLabel(_ status: ICAuthorizationStatus) -> String {
        if status == .authorized { return "已授权" }
        if status == .denied { return "已拒绝" }
        if status == .restricted { return "受系统限制" }
        if status == .notDetermined { return "还没问过" }
        return "未知(\(status.rawValue))"
    }

    static func isAuthorized(_ status: ICAuthorizationStatus) -> Bool {
        status == .authorized
    }

    /// 找不设备时的分层结论。
    ///
    /// 三种情况的现象一样（界面上什么都没有），但原因完全不同，
    /// 所以必须分开说，不然用户只能靠猜着换线。
    private func diagnoseNoDevice() {
        let count = browser.devices?.count ?? 0

        if !browser.isBrowsing {
            log(.fail, "浏览器没启动起来", detail: """
            ICDeviceBrowser.start() 之后 isBrowsing 还是 false，
            说明框架层就没跑，跟相机无关。退出 App 重开再点一次。
            """)
            return
        }
        if addCount > 0 || count > 0 {
            log(.fail, "系统看到了设备，但没有一台被当成相机", detail: """
            枚举到 \(count) 台，didAdd 回调 \(addCount) 次。
            线和接口是好的，问题在相机报给系统的身份。
            检查 USB 连接方式是不是「遥控拍摄」，以及设置弹窗关掉没有。
            """)
            return
        }
        log(.fail, "20 秒内系统一台 USB 设备都没枚举到", detail: """
        这一级只反映 iPhone 有没有认到设备，跟 App 代码无关。
        按顺序做，每一步都能独立得出结论：

        ① 打开系统「照片」App，看底部有没有出现「导入」。
           有 → 线和相机模式都没问题，问题在授权或 App；
           没有 → iPhone 根本没认到这台相机，先别改代码。

        ② 换一根线。随手的充电线大多只走电源两芯，枚举不到设备。

        ③ 相机上「遥控拍摄设置」那个提示框按「关闭」，退回拍摄画面。
           弹窗还开着的时候，相机没完成 USB 切换。

        ④ 相机「设置 → USB → USB电源供给」改成关。
           开着的时候相机会向手机要电，iOS 可能直接拒绝这个配件。

        ⑤ iPhone 保持解锁，插上后别切到别的 App。

        ⑥ 拔线，等 3 秒再插，插上后等相机屏幕出现 PC 标识再点开始。
        """)
    }

    /// 复制成纯文本，方便贴出来。
    ///
    /// 开头这段是分层快照：授权、过滤条件、枚举数量、原始设备描述。
    /// 后面日志里的结论都建立在它之上，所以放在一起，别只贴日志。
    var reportText: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let info = Bundle.main.infoDictionary
        let ver = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let cameraUsage = info?["NSCameraUsageDescription"] as? String

        var out = "CamCoach 探针报告\n"
        out += "时间：\(f.string(from: Date()))\n"
        out += "版本：\(ver)（\(build)）\n"
        out += "系统：\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)\n"
        out += "声明 NSCameraUsageDescription：\(cameraUsage == nil ? "缺失" : "有")\n"
        out += "\n-- 分层快照 --\n"
        out += "内容授权：\(contentsAuth)    控制授权：\(controlAuth)\n"
        out += "过滤条件：\(browseMask)    浏览器在跑：\(browsingNow ? "是" : "否")\n"
        out += "枚举到的设备：\(enumeratedCount)    didAdd 回调：\(addCount)\n"
        out += "当前相机：\(deviceLabel)\n"
        for d in rawDevices {
            out += "  · \(d)\n"
        }
        out += "\n-- 探测记录（共 \(attempts) 轮）--\n"

        let clock = DateFormatter()
        clock.dateFormat = "HH:mm:ss.SSS"
        for l in logs {
            let tag: String
            switch l.level {
            case .info: tag = "[·]"
            case .ok: tag = "[OK]"
            case .fail: tag = "[X]"
            case .warn: tag = "[!]"
            }
            out += "\(tag) \(clock.string(from: l.at))  \(l.text)\n"
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

        // 会话必须关掉。
        //
        // 不关的话，相机在系统侧一直算「已被本机占用」：下一轮扫描时
        // ICDeviceBrowser 不会把这个设备重新报出来，devices 也是空的。
        // 现象就是第一次能连、第二次一台都找不到。
        if cam.hasOpenSession {
            do {
                try await cam.requestCloseSession()
                log(.info, "已关闭相机会话")
            } catch {
                log(.warn, "关闭会话失败", detail: error.localizedDescription
                    + "\n下一轮可能枚举不到相机，重启 App 可以清掉")
            }
        }
    }

    private func probeLink(on cam: ICCameraDevice) {
        let session = SonyPtpSession(camera: cam)

        // ---- 1. 命令通道。GetDeviceInfo 不需要索尼认证，是整条链上最干净的一级：
        // 能读出来就同时证明「USB 枚举通了、会话通了、命令通道通了」。
        main { self.phase = "读设备信息" }
        do {
            let raw = try session.deviceInfoRaw()
            if let raw, let info = SonyDeviceInfo.parse(raw) {
                log(.ok, "命令通道通了，相机在应答", detail: """
                厂商扩展：\(info.vendorLabel)
                厂商：\(info.manufacturer.isEmpty ? "未提供" : info.manufacturer)
                型号：\(info.modelLabel)
                固件：\(info.deviceVersion.isEmpty ? "未提供" : info.deviceVersion)
                标准版本：0x\(String(format: "%04X", info.standardVersion))
                操作 \(info.operationCount) 条，属性 \(info.propertyCount) 条
                """)
                if !info.isSony {
                    log(.warn, "厂商扩展不是索尼",
                        detail: "私有命令 0x92xx / D2xx 多半发不通，后面很可能全部失败")
                }
            } else {
                log(.warn, "相机应答了，但设备信息解不出来", detail: """
                回包 \(raw?.count ?? 0) 字节。
                前 16 字节：\(raw.map { $0.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ") } ?? "空")
                这台相机的 DeviceInfo 结构和标准 PTP 不一样，得按这份字节重新对格式。
                """)
            }
        } catch {
            log(.fail, "GetDeviceInfo 失败：\(error.localizedDescription)", detail: """
            这一步不需要索尼认证。失败说明命令通道本身没通，常见原因：
            ① 相机被系统「照片」App 占着（回桌面把它划掉）
            ② 会话没真正打开
            ③ 这台相机不接受 ImageCaptureCore 转发的命令
            """)
            finish("命令通道不通")
            return
        }

        // ---- 2. 索尼认证
        main { self.phase = "索尼认证" }
        do {
            let ver = try session.authenticate()
            log(.ok, "认证通过", detail: "相机声明 PTP 协议版本 "
                + String(format: "0x%04X", ver))
        } catch {
            let done = session.authTrace.isEmpty ? "（第一步就没过）" : session.authTrace.joined(separator: "\n")
            log(.fail, "认证失败：\(error.localizedDescription)", detail: """
            已经走过的步骤：
            \(done)

            四步顺序是 0x9201[1,0,0] → 0x9201[2,0,0] → 0x9202[0x012C/0x00C8] → 0x9201[3,0,0]。
            卡在 0x9201[1] 一般是相机不在遥控模式；
            卡在 0x9202 一般是固件不认这两个协议版本。
            认证不过，后面什么都读不到，这里就停。
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
        main {
            self.logs.append(ProbeLog(level: level, text: text, detail: detail, at: Date()))
        }
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
        // 不管是什么类型，先原样记下来。原来这里 `as? ICCameraDevice` 失败就
        // 静默 return，一行日志都不留——「系统明明看到了设备」这件事就丢了，
        // 排查时会误判成「系统一台设备都没看到」，方向直接跑偏。
        let dump = String(describing: device)
        main {
            self.addCount += 1
            self.rawDevices.append(dump)
        }
        log(.info, "系统报来一台设备", detail: dump)

        guard let cam = device as? ICCameraDevice else {
            log(.warn, "这台不是相机类设备（\(type(of: device))）", detail: """
            只有 ICCameraDevice 才能发 PTP 命令。出现这种通常意味着：
            相机的 USB 连接方式停在「MTP」或「存储」，没选「遥控拍摄」；
            或者「遥控拍摄设置」那个弹窗还开着，没退回拍摄画面。
            """)
            return
        }
        adopt(cam, source: "didAdd 回调")
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        guard let cam = device as? ICCameraDevice, cam == camera else { return }
        camera = nil
        main { self.deviceLabel = "设备已断开" }
        // 第二次枚举不到的原因常常就在这里：设备其实是被系统摘掉了。
        log(.warn, "相机从系统里消失了", detail: "\(cam.name ?? "未命名") 被移除，"
            + "下一轮扫描要从零重新发现它")
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

/// 保证 continuation 只被 resume 一次。
///
/// 授权回调可能来、8 秒超时也可能到，两个都 resume 会直接崩在
/// "SWIFT TASK CONTINUATION MISUSE"。用一个带锁的一次性开关拦住。
private final class ResumeOnce {
    private var cont: CheckedContinuation<ICAuthorizationStatus, Never>?
    private let lock = NSLock()

    init(_ c: CheckedContinuation<ICAuthorizationStatus, Never>) {
        cont = c
    }

    func resume(_ status: ICAuthorizationStatus) {
        lock.lock()
        let c = cont
        cont = nil
        lock.unlock()
        c?.resume(returning: status)
    }
}
