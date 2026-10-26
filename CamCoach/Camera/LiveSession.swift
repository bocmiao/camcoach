// SPDX-License-Identifier: Apache-2.0
import Foundation
import ImageCaptureCore
import UIKit

/// 实时取景。
///
/// 一条后台循环，每轮做两件事：抓一帧取景、定期读一次全部属性。
/// 两个动作走同一个 PTP 通道，所以必须串行——这也是整件事只能有一个
/// 循环在跑的原因：探针和取景同时开，事务号会互相打乱。
///
/// 帧是索尼的 JPEG 快照，不是视频流。`0xFFFFC002` 这个虚拟对象每次
/// GetObject 都返回当时那一帧，因此帧率取决于相机出图速度、传输和
/// UIImage 解码，别指望固定值，界面上直接显示实测值。
final class LiveSession: ObservableObject {

    static let shared = LiveSession()

    @Published private(set) var frame: UIImage?
    @Published private(set) var readout = CameraReadout.empty
    @Published private(set) var fps: Double = 0
    @Published private(set) var frameCount = 0
    @Published private(set) var running = false
    @Published private(set) var lastError: String?
    /// 连续抓不到帧的次数，用来判断是「偶发」还是「真断了」。
    @Published private(set) var missCount = 0
    /// 刚拍下来的那张。取景循环拍完会把它回传给这里。
    @Published private(set) var lastShot: UIImage?
    /// 快门正在进行中。拍一张要一秒多，期间必须把按钮按住不让再点。
    @Published private(set) var capturing = false
    /// 拍摄出问题时给用户看的一句话，成功就清空。
    @Published private(set) var captureNote: String?
    @Published private(set) var shotCount = 0

    private var camera: ICCameraDevice?
    private let queue = DispatchQueue(label: "camcoach.liveview", qos: .userInitiated)
    private let gate = NSLock()
    private var stopRequested = false
    private var captureRequested = false
    /// 单条兜底读的轮次。整块里读不到的项不能每轮都去撞一次，
    /// 但又不能只试一次——用户中途拧一下补偿旋钮就变了。
    private var singleReadRound = 0

    private init() {}

    /// 属性每这么多帧读一次。331 条属性一次要几十毫秒，
    /// 每帧都读会把帧率压下去，而参数变化远没有那么快。
    private let propertyEveryNFrames = 4
    private let frameInterval: TimeInterval = 0.06

    // MARK: - 对外

    func attach(_ cam: ICCameraDevice) {
        if camera !== cam {
            stop()
            camera = cam
            lastError = nil
        }
    }

    var hasCamera: Bool { camera != nil }

    func start() {
        guard !running else { return }
        guard let cam = camera else {
            lastError = "还没有相机。点右上角的扳手做一次相机自检，连上之后再回来。"
            return
        }
        running = true
        lastError = nil
        captureNote = nil
        missCount = 0
        frameCount = 0
        setStop(false)
        setCaptureRequest(false)

        Task {
            if !cam.hasOpenSession {
                do {
                    try await cam.requestOpenSession()
                } catch {
                    publish(error: "打开会话失败：\(error.localizedDescription)")
                    finish()
                    return
                }
                try? await Task.sleep(nanoseconds: 900_000_000)
            }
            queue.async { [weak self] in self?.loop(on: cam) }
        }
    }

    func stop() {
        setStop(true)
        running = false
        capturing = false
    }

    /// 按一下快门。
    ///
    /// 真正的动作交给取景循环去做，因为 PTP 通道是独占的：
    /// 在这边另起一条线去发命令，会和正在抓帧的循环抢事务号，两边都坏。
    /// 这里只挂一个请求，循环下一圈自己取走。
    func capture() {
        guard running, !capturing else { return }
        capturing = true
        captureNote = nil
        setCaptureRequest(true)
    }

    /// 把拍到的图存进系统相册。
    ///
    /// 单独留一个方法而不是拍完自动存：自动存会在第一次弹权限框，
    /// 而权限框弹出时取景循环还在跑，用户看到的是「画面卡住了」，
    /// 很难联想到是权限。手动点一下，因果关系清楚。
    func saveLastShot(_ image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    }

    // MARK: - 主循环

    private func loop(on cam: ICCameraDevice) {
        let session = SonyPtpSession(camera: cam)

        // 认证。取景和属性都建立在它之上，失败就没必要继续空转。
        do {
            _ = try session.authenticate()
        } catch {
            publish(error: "认证失败：\(error.localizedDescription)")
            finish()
            return
        }

        var windowFrames = 0
        var windowStart = Date()
        var tick = 0
        var misses = 0

        while !isStopped() {
            if tick % propertyEveryNFrames == 0 {
                if let props = try? session.readProperties(), !props.isEmpty {
                    var r = CameraReadout.decode(props)
                    // 整块里没有的项，隔一阵用单条读补一次。
                    // 每 8 轮（约 16 秒）试一次，够跟上手拧旋钮的节奏，
                    // 又不会让取景帧率被这些必然失败的请求拖下去。
                    if !r.missingFields.isEmpty {
                        singleReadRound += 1
                        if singleReadRound % 8 == 1 {
                            fillBySingleRead(&r, session: session)
                        }
                    }
                    let snapshot = r
                    DispatchQueue.main.async { self.readout = snapshot }
                }
            }

            // 快门优先。拍的这一下会占住通道一两秒，取景会短暂停住，这是正常的：
            // 相机在曝光、存图，本来就没法同时出取景帧。
            if takeCaptureRequest() {
                shoot(session: session)
            }

            var gotFrame = false
            // liveViewFrame 返回 Data?，try? 之后已经压成一层 Optional，直接绑到 data。
            if let data = try? session.liveViewFrame(), let image = UIImage(data: data) {
                gotFrame = true
                windowFrames += 1
                DispatchQueue.main.async {
                    self.frame = image
                    self.frameCount += 1
                }
            }

            if gotFrame {
                if misses > 0 {
                    misses = 0
                    DispatchQueue.main.async { self.missCount = 0 }
                }
            } else {
                misses += 1
                // 连丢 30 帧基本就是相机掉线或者退出了遥控模式。
                if misses % 10 == 0 {
                    let n = misses
                    DispatchQueue.main.async { self.missCount = n }
                }
                if misses >= 30 {
                    publish(error: "连续 30 帧没抓到。检查相机是否还停在遥控拍摄（屏幕应有 PC 标识）。")
                    break
                }
            }

            let dt = Date().timeIntervalSince(windowStart)
            if dt >= 1.0 {
                let f = Double(windowFrames) / dt
                windowFrames = 0
                windowStart = Date()
                DispatchQueue.main.async { self.fps = f }
            }

            tick += 1
            Thread.sleep(forTimeInterval: frameInterval)
        }

        session.disconnect()
        finish()
    }

    // MARK: - 单条兜底

    /// 整块属性里读不到的项，改用标准 PTP 的单条读再试一次。
    ///
    /// 只处理「整块没给」这一种情况：整块给了但值认不出，不是这里的事。
    /// 读到了就把这一项从 `missingFields` 里摘掉，界面上立刻变成真实值；
    /// 读不到就原样留着，界面继续显示「机身未给」——那才是事实。
    private func fillBySingleRead(_ r: inout CameraReadout, session: SonyPtpSession) {
        if r.missingFields.contains("补偿") {
            // 私有段优先。索尼不认这条命令时会回 0x2005，readPropRaw 返回 nil。
            for code in [CameraProp.exposureComp, CameraProp.exposureCompStd] {
                guard let d = try? session.readPropRaw(code),
                      let v = CameraReadout.signed16(d) else { continue }
                r.exposureComp = CameraReadout.evText(v)
                r.missingFields.removeAll { $0 == "补偿" }
                break
            }
        }
        if r.missingFields.contains("模式") {
            if let d = try? session.readPropRaw(CameraProp.exposureProgram),
               let v = CameraReadout.unsigned16(d) {
                r.mode = CameraReadout.modeText(v)
                r.missingFields.removeAll { $0 == "模式" }
            }
        }
    }

    // MARK: - 快门

    /// 拍一张，然后把图取回来。
    ///
    /// 这一步会把取景循环占住一到两秒，期间界面上的画面是静止的。
    /// 不另开线程并发去做：PTP 通道独占，两个命令交错发出去相机只会回 DeviceBusy。
    private func shoot(session: SonyPtpSession) {
        do {
            try session.captureStill()
        } catch {
            DispatchQueue.main.async {
                self.capturing = false
                self.captureNote = "快门没按下去：\(error.localizedDescription)"
            }
            return
        }
        if let jpeg = try? session.pollCapturedJPEG(timeout: 6), let image = UIImage(data: jpeg) {
            DispatchQueue.main.async {
                self.lastShot = image
                self.capturing = false
                self.captureNote = nil
                self.shotCount += 1
            }
        } else {
            DispatchQueue.main.async {
                self.capturing = false
                // 照片大概率拍到了，只是相机没回传。这句要写清「照片在卡里」，
                // 不然用户会以为白拍了。
                self.captureNote = "快门按下了，照片应该在相机卡里；相机没把它回传过来（要相机开着自动回传）。"
                self.shotCount += 1
            }
        }
    }

    // MARK: - 小工具

    private func setStop(_ v: Bool) {
        gate.lock()
        stopRequested = v
        gate.unlock()
    }

    private func isStopped() -> Bool {
        gate.lock()
        let v = stopRequested
        gate.unlock()
        return v
    }

    private func setCaptureRequest(_ v: Bool) {
        gate.lock()
        captureRequested = v
        gate.unlock()
    }

    /// 取走一次快门请求。取走即清零，避免连按变成连拍。
    private func takeCaptureRequest() -> Bool {
        gate.lock()
        let v = captureRequested
        captureRequested = false
        gate.unlock()
        return v
    }

    private func publish(error: String) {
        DispatchQueue.main.async { self.lastError = error }
    }

    private func finish() {
        DispatchQueue.main.async {
            self.running = false
            self.fps = 0
            self.capturing = false
        }
    }
}
