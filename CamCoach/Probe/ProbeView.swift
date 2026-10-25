// SPDX-License-Identifier: Apache-2.0
import ImageCaptureCore
import SwiftUI
import UIKit

struct CheckRow: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let ok: Bool
}

/// 连相机这一页。
///
/// 前面加了一组硬条件检查。这几条任何一条不满足，连上也会秒断，
/// 而且现象都一样（点开始没反应），不先确认就只能靠猜。
struct ProbeView: View {

    let data: CameraData

    @StateObject private var probe = CameraProbe()
    @State private var confirmed: Set<String> = []
    @State private var copied = false

    var body: some View {
        List {
            preflightSection
            deviceSection
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
        } header: {
            Text("相机")
        } footer: {
            if preflightDone {
                Text("相机用数据线连 iPhone，连接方式选「遥控拍摄」（屏幕显示 -PC-），再点开始。")
            } else {
                Text("上面还有 \(data.connectChecks.count - confirmed.count) 项没确认。")
            }
        }
    }

    // MARK: - 环境自检

    private var selfCheckSection: some View {
        Section {
            ForEach(buildRows()) { r in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: r.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(r.ok ? Color.green : Color.orange)
                        .font(.system(size: 15))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.label).font(.subheadline)
                        Text(r.value)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("环境自检")
        }
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
                Text("右上角「复制」把整份记录导出来，就知道下一步该做什么了。")
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

    private func buildRows() -> [CheckRow] {
        var out: [CheckRow] = []

        let info = Bundle.main.infoDictionary
        let ver = info?["CFBundleShortVersionString"] as? String ?? "未知"
        let build = info?["CFBundleVersion"] as? String ?? "未知"
        out.append(CheckRow(label: "版本", value: "\(ver)（\(build)）", ok: true))

        let dev = UIDevice.current
        out.append(CheckRow(label: "系统", value: "\(dev.systemName) \(dev.systemVersion)", ok: true))
        out.append(CheckRow(label: "机型", value: dev.model, ok: true))

        let osv = ProcessInfo.processInfo.operatingSystemVersion
        let ptpOK = osv.majorVersion > 15 || (osv.majorVersion == 15 && osv.minorVersion >= 2)
        out.append(CheckRow(
            label: "PTP 命令通道",
            value: ptpOK ? "系统版本满足（要 15.2 以上）" : "系统版本偏低，需要 iOS 15.2 以上",
            ok: ptpOK
        ))

        // 真引用一次，链接器才会真的去要 ImageCaptureCore。
        _ = ICCameraDevice.self
        out.append(CheckRow(
            label: "ImageCaptureCore",
            value: "框架已链接，ICCameraDevice 可引用",
            ok: true
        ))

        return out
    }
}
