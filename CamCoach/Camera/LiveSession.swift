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

    private var camera: ICCameraDevice?
    private let queue = DispatchQueue(label: "camcoach.liveview", qos: .userInitiated)
    private let gate = NSLock()
    private var stopRequested = false

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
            lastError = "还没有相机。先去「连相机」点开始探测，连上之后再回来。"
            return
        }
        running = true
        lastError = nil
        missCount = 0
        frameCount = 0
        setStop(false)

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
                    let r = CameraReadout.decode(props)
                    DispatchQueue.main.async { self.readout = r }
                }
            }

            var gotFrame = false
            if let jpeg = try? session.liveViewFrame(), let data = jpeg,
               let image = UIImage(data: data) {
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

    private func publish(error: String) {
        DispatchQueue.main.async { self.lastError = error }
    }

    private func finish() {
        DispatchQueue.main.async {
            self.running = false
            self.fps = 0
        }
    }
}
