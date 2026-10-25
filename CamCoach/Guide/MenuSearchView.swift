// SPDX-License-Identifier: Apache-2.0
import SwiftUI
import UIKit

/// 反查：知道自己想干什么，不知道菜单在哪。
///
/// 相机的菜单是按功能分类的，新手心里的分类和 Sony 的分类经常对不上
/// （「关快门声」在音频信号里，「格式化卡」在拍摄栏里）。这里按「想做的事」
/// 建索引，搜你脑子里的说法。
struct MenuSearchView: View {

    let data: CameraData

    @State private var query = ""
    @State private var copiedID: String?

    var body: some View {
        List {
            if results.isEmpty {
                emptyState
            } else {
                ForEach(results) { m in
                    row(m)
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $query, prompt: "试试「卡」「声」「网格」")
        .navigationTitle("找设置")
        .navigationBarTitleDisplayMode(.large)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("没找到「\(query)」")
                .font(.subheadline.weight(.medium))
            Text("换个词试试。这里收的是最常被找错位置的十几项，不是全部菜单。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private func row(_ m: MenuEntry) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(m.want)
                .font(.subheadline.weight(.semibold))

            HStack(alignment: .top, spacing: 10) {
                Text(m.path)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button {
                    UIPasteboard.general.string = m.path
                    copiedID = m.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        if copiedID == m.id { copiedID = nil }
                    }
                } label: {
                    Image(systemName: copiedID == m.id ? "checkmark" : "doc.on.doc")
                        .font(.footnote)
                        .foregroundStyle(copiedID == m.id ? Color.green : Color.accentColor)
                }
                .buttonStyle(.plain)
            }

            if !m.note.isEmpty {
                Label(m.note, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
        }
        .padding(.vertical, 4)
    }

    private var results: [MenuEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return data.menus }
        return data.menus.filter {
            $0.want.contains(q) || $0.path.contains(q) || $0.note.contains(q)
        }
    }
}
