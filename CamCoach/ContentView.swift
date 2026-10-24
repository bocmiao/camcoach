// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import UIKit
import ImageCaptureCore

struct CheckRow: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let ok: Bool
}

struct ContentView: View {

    @StateObject private var probe = CameraProbe()
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {
                deviceSection
                selfCheckSection
                logSection
            }
            .navigationTitle("取景助手 · 探针")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        UIPasteboard.general.string = probe.reportText
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            copied = false
                        }
                    } label: {
                        Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .disabled(probe.logs.isEmpty)
                }
            }
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
            .disabled(probe.running)
        } header: {
            Text("相机")
        } footer: {
            Text("相机用数据线连 iPhone，连接方式选「遥控拍摄」（屏幕显示 -PC-），再点开始。")
        }
    }

    // MARK: - 自检（v1.0 的内容，保留）

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
                Text("右上角「复制」把整份记录贴给我，就知道下一步该做什么了。")
            }
        }
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
