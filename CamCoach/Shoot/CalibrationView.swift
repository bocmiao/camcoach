// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import UIKit

/// 标定采样。
///
/// 这不是给用户的功能，是给阈值找依据用的。现在「亮部超过 2% 算死了」
/// 这类判断全是经验值，没拿真实画面校准过。这里的做法是：
/// 对着同一个场景调不同曝光各记一笔，攒够二十来条，
/// 把「你觉得这张能不能用」和「亮部当时占了多少」对起来，
/// 阈值就变成测出来的，而不是猜的。
struct CalibrationView: View {

    @StateObject private var store = CalibrationStore.shared
    @StateObject private var live = LiveSession.shared
    @AppStorage(CameraSettings.focalKey) private var focal = CameraSettings.defaultFocal
    @Environment(\.dismiss) private var dismiss

    @State private var lastVerdict: String?
    @State private var copied = false

    private let verdicts = ["能看", "糊了", "过曝", "欠曝"]

    var body: some View {
        List {
            currentSection
            recordSection
            recordsSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("标定采样")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("完成") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    UIPasteboard.general.string = store.text
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Label(copied ? "已复制" : "复制",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .disabled(store.records.isEmpty)
            }
        }
    }

    // MARK: - 当前一帧

    private var currentSection: some View {
        Section {
            if let s = live.stats {
                statLine("亮部（≥250）", String(format: "%.2f%%", s.highlight * 100))
                statLine("暗部（≤8）", String(format: "%.2f%%", s.shadow * 100))
                statLine("平均亮度", String(format: "%.1f%%", s.mean * 100))
                statLine("相机参数",
                         "\(live.readout.shutter) · \(live.readout.aperture) · ISO \(live.readout.iso)")
                statLine("焦距", "\(focal)mm")
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.secondary)
                    Text(live.running ? "正在取景，等第一帧…" : "还没开始取景。点「完成」回取景页按「开始取景」，再回来记。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } header: {
            Text("这一帧")
        } footer: {
            if live.stats != nil {
                Text("数值每帧都在变，记下来的是你按下那一瞬间的。对着同一个场景拧曝光补偿，各记一次，数据才用得上。")
            }
        }
    }

    private func statLine(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 记一笔

    private var recordSection: some View {
        Section {
            HStack(spacing: 8) {
                ForEach(verdicts, id: \.self) { v in
                    Button {
                        record(v)
                    } label: {
                        VStack(spacing: 3) {
                            Text(v)
                                .font(.footnote.weight(.medium))
                            Text("\(store.records.filter { $0.verdict == v }.count)")
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(background(for: v))
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .disabled(live.stats == nil)
                }
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        } header: {
            Text("这张怎么样")
        } footer: {
            if let v = lastVerdict {
                Text("刚记了一条「\(v)」。")
                    .foregroundStyle(.secondary)
            } else {
                Text("按钮下面的数字是当前已记的条数。四种判断各攒几条、覆盖亮和暗，阈值才定得住。")
            }
        }
    }

    private func background(for verdict: String) -> Color {
        switch verdict {
        case "能看": return Color.green.opacity(0.16)
        case "糊了": return Color.blue.opacity(0.14)
        case "过曝": return Color.red.opacity(0.14)
        default: return Color.orange.opacity(0.14)
        }
    }

    private func record(_ verdict: String) {
        guard let s = live.stats else { return }
        store.add(SampleRecord(
            at: Date(),
            highlight: s.highlight,
            shadow: s.shadow,
            mean: s.mean,
            shutter: live.readout.shutter,
            aperture: live.readout.aperture,
            iso: live.readout.iso,
            focalMM: focal,
            verdict: verdict))
        lastVerdict = verdict
    }

    // MARK: - 已记录

    private var recordsSection: some View {
        Section {
            if store.records.isEmpty {
                Text("还没记。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.records.reversed()) { r in
                    HStack(spacing: 10) {
                        Text(r.verdict)
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(background(for: r.verdict))
                            .clipShape(Capsule())
                        Text(String(format: "亮 %.1f%% · 暗 %.1f%%", r.highlight * 100, r.shadow * 100))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Text(r.shutter)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    // 这里用 swipeActions 而不是 onDelete：列表是倒序显示的，
                    // onDelete 给的 IndexSet 是倒序后的下标，直接拿去删原数组会删错行。
                    .swipeActions {
                        Button(role: .destructive) {
                            store.remove(id: r.id)
                        } label: {
                            Text("删除")
                        }
                    }
                }

                Button(role: .destructive) {
                    store.clear()
                    lastVerdict = nil
                } label: {
                    Text("全部清空")
                        .font(.footnote)
                        .frame(maxWidth: .infinity)
                }
            }
        } header: {
            HStack {
                Text("已记录")
                Spacer()
                Text("\(store.records.count) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            if !store.records.isEmpty {
                Text("右上角「复制」，把这段文字发回来。表头已经带好单位，直接贴进表格就能看分布。")
            }
        }
    }
}
