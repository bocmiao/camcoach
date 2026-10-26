// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import UIKit

/// 取景页。相机连上之后，这里才是真正用来拍照的界面。
///
/// 左边是相机的实时画面（叠三分线和中心十字），下面是相机里读回来的
/// 真实参数，再下面是本地算出来的一两句话建议。
struct LiveViewScreen: View {

    @StateObject private var live = LiveSession.shared
    @State private var stats: ExposureStats?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                imageArea
                if let err = live.lastError {
                    errorRow(err)
                }
                paramBar
                statusBar
                adviceList
                controlBar
                footnote
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("取景")
        .navigationBarTitleDisplayMode(.inline)
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
                Text("先去「连相机」点开始探测，连上再回来")
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

    private func chip(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 9))
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
