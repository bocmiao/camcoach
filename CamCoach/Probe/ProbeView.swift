// SPDX-License-Identifier: Apache-2.0
import ImageCaptureCore
import SwiftUI
import UIKit

/// 连相机这一页。
///
/// 前面加了一组硬条件检查。这几条任何一条不满足，连上也会秒断，
/// 而且现象都一样（点开始没反应），不先确认就只能靠猜。
struct ProbeView: View {

    let data: CameraData

    @StateObject private var probe = CameraProbe.shared
    @State private var confirmed: Set<String> = []
    @State private var copied = false

    var body: some View {
        List {
            preflightSection
            deviceSection
            if let frame = probe.previewFrame {
                previewSection(frame)
            }
            selfCheckSection
            logSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("连相机")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    UIPasteboard.general.string = probe.reportText
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copied = false
                    }
                } label: {
                    Label(copied ? "已复制" : "复制",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .disabled(probe.logs.isEmpty)
            }
        }
    }

    // MARK: - 连接前

    private var preflightSection: some View {
        Section {
            ForEach(data.connectChecks) { c in
                let on = confirmed.contains(c.id)
                Button {
                    if on { confirmed.remove(c.id) } else { confirmed.insert(c.id) }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: on ? "checkmark.square.fill" : "square")
                            .font(.system(size: 18))
                            .foregroundStyle(on ? Color.accentColor : Color.secondary.opacity(0.5))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(c.title)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Text(c.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            HStack {
                Text("连之前先确认")
                Spacer()
                Text("\(confirmed.count)/\(data.connectChecks.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("这 6 条任缺一条，现象都是「点了没反应」，只能靠猜。")
        }
    }

    // MARK: - 设备与探针

    private var deviceSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: probe.running ? "dot.radiowaves.left.and.right" : "camera")
                    .font(.system(size: 20))
                    .foregroundStyle(probe.running ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(probe.deviceLabel).font(.subheadline.weight(.medium))
                    Text(probe.phase).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)

            Button {
                probe.begin()
            } label: {
                HStack {
                    Spacer()
                    if probe.running {
                        ProgressView().padding(.trailing, 6)
                    }
                    Text(probe.running ? "正在探测…" : "开始探测")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }
            }
            .disabled(probe.running || !preflightDone)

            // 兜底。只在设备卡死（换线重插也回不来）时用：
            // 丢了引用再换一个新浏览器，等于让系统把它当成刚插上。
            Button {
                probe.reset()
            } label: {
                HStack {
                    Spacer()
                    Text("断开并重新发现")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .disabled(probe.running)
        } header: {
            Text("相机")
        } footer: {
            if preflightDone {
                Text("选「遥控拍摄」后，那个设置提示框按「关闭」退回拍摄画面，再点开始。弹窗还开着时相机没完成 USB 切换。")
            } else {
                Text("上面还有 \(data.connectChecks.count - confirmed.count) 项没确认。")
            }
        }
    }

    // MARK: - 取景画面

    /// 探针抓到的那一帧。有图就说明 PTP 画面通路真的通了，
    /// 这比任何日志都直接。
    private func previewSection(_ image: UIImage) -> some View {
        Section {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        } header: {
            Text("取景画面")
        } footer: {
            Text("这一帧是相机通过 PTP 送过来的。能看到它，说明读取参数和连续取景都能做。")
        }
    }

    // MARK: - 自检

    /// 找不到相机时，这一栏是唯一有信息量的地方。
    ///
    /// 五级按「由外到内」排：授权 → 声明 → 枚举 → 过滤 → 环境。
    /// 上面一级没通，下面几级的结论都不作数，所以从上往下看，
    /// 第一个红的就是断点。
    private var selfCheckSection: some View {
        Section {
            ladderRow(1, "访问授权",
                      "内容 \(probe.contentsAuth)　控制 \(probe.controlAuth)",
                      authState)
            ladderRow(2, "用途声明",
                      cameraUsageDeclared
                        ? "NSCameraUsageDescription 已声明"
                        : "缺 NSCameraUsageDescription，系统会静默不枚举",
                      cameraUsageDeclared ? LadderState.pass : .fail)
            ladderRow(3, "设备",
                      probe.hasCamera
                        ? "已持有相机，本轮直接复用，不再重新枚举"
                        : "浏览器\(probe.browsingNow ? "在跑" : "没在跑")，"
                            + "枚举到 \(probe.enumeratedCount) 台，didAdd 回调 \(probe.addCount) 次",
                      probe.hasCamera ? LadderState.pass : enumerateState)
            ladderRow(4, "过滤条件", probe.browseMask,
                      probe.browseMask == "未设置" ? .unknown : .pass)
            ladderRow(5, "环境",
                      "\(appVersion)　\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
                      .pass)
        } header: {
            Text("自检")
        } footer: {
            Text("从上往下看，第一个红色就是断点。右上角「复制」会把这份状态连同日志一起导出。")
        }
    }

    private func ladderRow(_ n: Int, _ title: String, _ value: String,
                           _ state: LadderState) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background(Color.secondary.opacity(0.15))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline)
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Image(systemName: state.icon)
                .font(.system(size: 14))
                .foregroundStyle(state.color)
                .padding(.top, 1)
        }
        .padding(.vertical, 2)
    }

    // MARK: - 日志

    private var logSection: some View {
        Section {
            if probe.logs.isEmpty {
                Text("还没有记录。点上面的「开始探测」。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(probe.logs) { l in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: l.icon)
                            .font(.system(size: 12))
                            .foregroundStyle(color(of: l.level))
                            .padding(.top, 3)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(l.text)
                                .font(.system(.caption, design: .monospaced))
                                .fixedSize(horizontal: false, vertical: true)
                            if let d = l.detail, !d.isEmpty {
                                Text(d)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            HStack {
                Text("探测记录")
                Spacer()
                Text("\(probe.logs.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            if !probe.logs.isEmpty {
                Text("日志会保留多轮，不清空。连点两次再复制，两次的差异会一起带走。")
            }
        }
    }

    // MARK: - 取值

    private var preflightDone: Bool {
        confirmed.count == data.connectChecks.count
    }

    private func color(of level: ProbeLog.Level) -> Color {
        switch level {
        case .info: return .secondary
        case .ok: return .green
        case .fail: return .red
        case .warn: return .orange
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let ver = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(ver)（\(build)）"
    }

    /// App 自己检查自己的 Info.plist。缺这条声明时系统静默不枚举设备，
    /// 光看现象是看不出来的，所以必须显式查一遍。
    private var cameraUsageDeclared: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil
    }

    private var authState: LadderState {
        if probe.contentsAuth == "已授权" && probe.controlAuth == "已授权" { return .pass }
        if probe.contentsAuth == "未查询" && probe.controlAuth == "未查询" { return .unknown }
        if probe.contentsAuth.contains("拒绝") || probe.controlAuth.contains("拒绝") { return .fail }
        return probe.running ? .waiting : .fail
    }

    private var enumerateState: LadderState {
        if probe.enumeratedCount > 0 { return .pass }
        if probe.running { return .waiting }
        if probe.addCount > 0 { return .fail }
        return .unknown
    }
}

/// 自检每一级的状态。语义是「这一级通了没有」，不是「好不好」，
/// 所以 unknown 用空心圈，不跟着报错变红。
enum LadderState {
    case pass, fail, waiting, unknown

    var icon: String {
        switch self {
        case .pass: return "checkmark.circle.fill"
        case .fail: return "xmark.circle.fill"
        case .waiting: return "circle.dotted"
        case .unknown: return "circle"
        }
    }

    var color: Color {
        switch self {
        case .pass: return .green
        case .fail: return .red
        case .waiting: return .orange
        case .unknown: return .secondary
        }
    }
}
