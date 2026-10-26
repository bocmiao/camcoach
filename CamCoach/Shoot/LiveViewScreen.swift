// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import UIKit

/// 取景页。相机连上之后，这里才是真正用来拍照的界面。
///
/// 上面是相机的实时画面（叠三分线、中心十字、高光斑马纹、直方图），
/// 下面是相机里读回来的真实参数，再下面是本地算出来的一两句话建议。
struct LiveViewScreen: View {

    let data: CameraData

    @StateObject private var live = LiveSession.shared
    /// 镜头焦距。相机不报这一项，而安全快门必须知道它，所以让用户选一次。
    @AppStorage(CameraSettings.focalKey) private var focal = CameraSettings.defaultFocal
    /// 弹出的那一页。用同一个状态管两种页，避免同一层挂两个 sheet。
    @State private var sheet: SheetKind?
    /// 「存到相册」点完之后的一句确认。
    @State private var savedNote: String?

    private enum SheetKind: Identifiable {
        case probe, calibration
        var id: Int { self == .probe ? 0 : 1 }
    }

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
                    sheet = .calibration
                } label: {
                    Label("标定采样", systemImage: "square.and.pencil")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    live.stop()
                    sheet = .probe
                } label: {
                    Label("相机自检", systemImage: "wrench.and.screwdriver")
                }
            }
        }
        .sheet(item: $sheet) { kind in
            switch kind {
            case .probe:
                NavigationStack { ProbeView(data: data) }
            case .calibration:
                NavigationStack { CalibrationView() }
            }
        }
        .onAppear { attachIfNeeded() }
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
                    // 斑马纹压在画面上、三分线下面：它是「这一片已经没细节了」的
                    // 警告，不该盖住构图用的辅助线。
                    if let z = live.zebra {
                        Image(uiImage: z)
                            .resizable()
                            .interpolation(.none)
                            .opacity(0.75)
                            .allowsHitTesting(false)
                    }
                    gridOverlay
                    if let s = live.stats {
                        histogram(s)
                            .frame(width: 128, height: 40)
                            .padding(8)
                            .frame(width: w, height: h, alignment: .bottomLeading)
                    }
                }
                .frame(width: w, height: h)
                .clipped()
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
        .frame(height: 292)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// 32 档亮度分布。
    ///
    /// 画成柱状而不是曲线：新手看的是「有没有堆在最左或最右」，
    /// 柱子贴不贴边比曲线好不好看重要。
    private func histogram(_ stats: ExposureStats) -> some View {
        Canvas { ctx, size in
            let bins = stats.histogram
            guard !bins.isEmpty else { return }
            let peak = max(bins.max() ?? 0, 0.0001)
            let bw = size.width / CGFloat(bins.count)
            var path = Path()
            for (i, v) in bins.enumerated() {
                let bh = size.height * CGFloat(v / peak)
                guard bh > 0.5 else { continue }
                let x = CGFloat(i) * bw
                path.addRect(CGRect(x: x, y: size.height - bh,
                                    width: max(bw - 1, 1), height: bh))
            }
            ctx.fill(path, with: .color(.white.opacity(0.82)))
        }
        .background(Color.black.opacity(0.38))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .allowsHitTesting(false)
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
            focalRow
            if !live.readout.missingFields.isEmpty && live.running {
                missingNote
            }
            if let note = live.captureNote {
                errorRow(note)
            }
        }
    }

    /// 焦距选择。
    ///
    /// 相机不通过 PTP 报当前焦距，而「手持安全快门」必须知道它——
    /// 写死 1/50 的话，24mm 端太保守、85mm 端太乐观。
    private var focalRow: some View {
        HStack(spacing: 8) {
            Text("镜头焦距")
                .font(.caption)
                .foregroundStyle(.secondary)
            Menu {
                ForEach(CameraSettings.focalChoices, id: \.self) { f in
                    Button {
                        focal = f
                    } label: {
                        if f == focal {
                            Label("\(f)mm", systemImage: "checkmark")
                        } else {
                            Text("\(f)mm")
                        }
                    }
                }
            } label: {
                Text("\(focal)mm")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(Capsule())
            }
            Text("手持安全快门按 \(safeShutterText) 算")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var safeShutterText: String {
        "1/\(focal)"
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
        return Advisor.review(live.readout, exposure: live.stats, focalMM: focal)
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
}
