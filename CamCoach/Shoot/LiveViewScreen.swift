// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import UIKit

/// 取景页。相机连上之后，这里才是真正用来拍照的界面。
///
/// 左边是相机的实时画面（叠三分线和中心十字），下面是相机里读回来的
/// 真实参数，再下面是本地算出来的一两句话建议。
struct LiveViewScreen: View {

    let data: CameraData

    @StateObject private var live = LiveSession.shared
    @State private var stats: ExposureStats?
    /// 相机自检页。它必须先停掉取景才能跑（同一条 PTP 通道），
    /// 所以这里用 sheet 而不是 tab：点开就盖住取景，退出就回来，因果关系直观。
    @State private var showProbe = false
    /// 「存到相册」点完之后的一句确认。
    @State private var savedNote: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                imageArea
                if let err = live.lastError {
                    errorRow(err)
                }
                params
                if let shot = live.lastShot {
                    shotRow(shot)
                }
                adviceList
                controls
                footnote
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("取景")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    live.stop()
                    showProbe = true
                } label: {
                    Label("相机自检", systemImage: "wrench.and.screwdriver")
                }
            }
        }
        .sheet(isPresented: $showProbe) {
            NavigationStack {
                ProbeView(data: data)
            }
        }
        .onAppear { attachIfNeeded() }
        .onChange(of: live.frameCount) { _ in refreshStats() }
    }

    // MARK: - 画面

    /// 画面固定按 1024×680 的宽高比摆放，三分线才能压在图像上而不是压在外框上。
    private var imageArea: some View {
        ZStack {
            Color.black
            GeometryReader { geo in
                let ratio: CGFloat = 1024.0 / 680.0
                let w = min(geo.size.width, geo.size.height * ratio)
                let h = w / ratio
                ZStack {
                    if let f = live.frame {
                        Image(uiImage: f)
                            .resizable()
                            .scaledToFill()
                    } else {
                        emptyHint
                    }
                    gridOverlay
                }
                .frame(width: w, height: h)
                .clipped()
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
        .frame(height: 292)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var emptyHint: some View {
        VStack(spacing: 6) {
            Image(systemName: live.hasCamera ? "camera.viewfinder" : "cable.connector.slash")
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.55))
            Text(live.hasCamera ? "点下面「开始取景」" : "还没有相机")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
            if !live.hasCamera {
                Text("点右上角的扳手，先做一次相机自检")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private var gridOverlay: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { p in
                for i in 1...2 {
                    let x = w * CGFloat(i) / 3
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: h))
                    let y = h * CGFloat(i) / 3
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: w, y: y))
                }
                let cx = w / 2
                let cy = h / 2
                p.move(to: CGPoint(x: cx - 11, y: cy))
                p.addLine(to: CGPoint(x: cx + 11, y: cy))
                p.move(to: CGPoint(x: cx, y: cy - 11))
                p.addLine(to: CGPoint(x: cx, y: cy + 11))
            }
            .stroke(Color.white.opacity(0.34), lineWidth: 0.8)
        }
        .allowsHitTesting(false)
    }

    // MARK: - 参数

    private var paramBar: some View {
        HStack(spacing: 8) {
            chip("快门", live.readout.shutter)
            chip("光圈", live.readout.aperture)
            chip("ISO", live.readout.iso)
            chip("补偿", live.readout.exposureComp)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            chip("模式", live.readout.mode)
            chip("对焦", live.readout.focus)
            chip("电量", live.readout.battery)
            chip("可拍", live.readout.shotsLeft)
        }
    }

    /// 两排参数 + 它们下面可能出现的说明。
    ///
    /// 合在一起是为了控制最外层 VStack 的子视图数量：SwiftUI 的
    /// ViewBuilder 最多吃 10 个直接子视图，超了会报一句看不出原因的
    /// 「Extra argument in call」。
    private var params: some View {
        VStack(spacing: 8) {
            paramBar
            statusBar
            if !live.readout.missingFields.isEmpty && live.running {
                missingNote
            }
            if let note = live.captureNote {
                errorRow(note)
            }
        }
    }

    private func chip(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(value == "—" ? Color.secondary.opacity(0.45) : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    /// 「机身没给」的说明。
    ///
    /// 不写这段话，用户看到「—」只会以为 App 坏了，然后去换线、重插。
    /// 把「是哪几项、为什么」直接说出来，问题就停在产品层，不进排查流程。
    private var missingNote: some View {
        let names = live.readout.missingFields.joined(separator: "、")
        let sentence = "这台机身没通过 PTP 报出「" + names + "」，所以那几格是「—」。"
            + "其余参数是相机真实值。"
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            Text(sentence)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - 建议

    private var adviceList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(advices) { a in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(color(of: a.level))
                        .frame(width: 7, height: 7)
                        .padding(.top, 5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.text)
                            .font(.subheadline.weight(.medium))
                        Text(a.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var advices: [Advice] {
        if live.frame == nil && !live.running {
            return [Advice(level: .good, text: "还没开始取景",
                           detail: "连上相机后点「开始取景」，参数和建议会跟着画面实时更新。")]
        }
        return Advisor.review(live.readout, exposure: stats)
    }

    private func color(of level: Advice.Level) -> Color {
        switch level {
        case .good: return .green
        case .warn: return .orange
        case .bad: return .red
        }
    }

    // MARK: - 控制

    private var controlBar: some View {
        HStack(spacing: 12) {
            Button {
                if live.running {
                    live.stop()
                } else {
                    attachIfNeeded()
                    live.start()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: live.running ? "stop.fill" : "play.fill")
                    Text(live.running ? "停止取景" : "开始取景")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(live.running ? Color.red.opacity(0.14) : Color.accentColor.opacity(0.16))
                .foregroundStyle(live.running ? Color.red : Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            VStack(alignment: .trailing, spacing: 1) {
                Text(String(format: "%.1f fps", live.fps))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                Text("\(live.frameCount) 帧")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 66)
        }
    }

    private var footnote: some View {
        Text("画面是相机一帧一帧送过来的 JPEG，不是视频流，1024×680。帧率取决于相机出图速度，显示的是实测值。")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 快门

    /// 取景开关 + 快门。两者都是「操作」，放在一起，不夹在参数中间。
    private var controls: some View {
        VStack(spacing: 10) {
            controlBar
            shutterBar
        }
    }

    private var shutterBar: some View {
        VStack(spacing: 8) {
            Button {
                live.capture()
            } label: {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.18), lineWidth: 2)
                        .frame(width: 66, height: 66)
                    Circle()
                        .fill(live.running && !live.capturing
                              ? Color.primary : Color.secondary.opacity(0.25))
                        .frame(width: 54, height: 54)
                    if live.capturing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!live.running || live.capturing)

            Text(live.capturing ? "正在拍…" : (live.running ? "拍一张" : "开始取景后才能拍"))
                .font(.caption2)
                .foregroundStyle(.secondary)
            if live.shotCount > 0 {
                Text("这次已拍 \(live.shotCount) 张")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    /// 拍完的缩略图。存不存由用户决定，不自动写相册——
    /// 自动写会在第一次弹权限框，而那时取景还在跑，看起来像卡死。
    private func shotRow(_ image: UIImage) -> some View {
        HStack(spacing: 10) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 62, height: 44)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text("刚拍的")
                    .font(.caption.weight(.medium))
                Text("照片本来就在相机卡里，这里是它回传的一份")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)

            Button {
                live.saveLastShot(image)
                savedNote = "已提交保存，去相册看看"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { savedNote = nil }
            } label: {
                Text(savedNote == nil ? "存相册" : "已提交")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.14))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func errorRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
                .padding(.top, 2)
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 取值

    private func attachIfNeeded() {
        if let cam = CameraProbe.shared.device {
            live.attach(cam)
        }
    }

    /// 每 4 帧算一次曝光统计。每帧都算没必要，64×64 也会占主线程时间。
    private func refreshStats() {
        guard live.frameCount > 0, live.frameCount % 4 == 0, let f = live.frame else { return }
        stats = Advisor.exposure(f)
    }
}
