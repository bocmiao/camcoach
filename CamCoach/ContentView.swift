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

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(buildRows()) { r in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: r.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(r.ok ? Color.green : Color.orange)
                                .font(.system(size: 16))
                            VStack(alignment: .leading, spacing: 3) {
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
                    Text("自检")
                } footer: {
                    Text("这一版只验证一件事：没有 Mac，能不能把 App 装到你手机上。全绿就说明链路通了。")
                }

                Section("下一版才会接相机") {
                    Text("枚举 USB 设备、发 PTP 命令、读拍摄参数、拉取景流——这些等自检全绿之后再进来，免得流水线问题和代码问题混在一起排查。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("取景助手")
            .navigationBarTitleDisplayMode(.inline)
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

        // 真引用一次这个类型，链接器才会真的去要 ImageCaptureCore。
        // 如果框架在目标 SDK 里不可用，这一行会直接编译失败——那正是我要知道的事。
        _ = ICCameraDevice.self
        out.append(CheckRow(
            label: "ImageCaptureCore",
            value: "框架已链接，ICCameraDevice 可引用",
            ok: true
        ))

        return out
    }
}
