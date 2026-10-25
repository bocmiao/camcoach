// SPDX-License-Identifier: Apache-2.0
import SwiftUI

/// 第一周该认的键，做成可勾选的清单。
///
/// 分组直接用按钮数据里的 level 字段（week1 / later），
/// 不在视图里另写一份名单，否则数据一改就对不上。
struct ChecklistView: View {

    let data: CameraData

    @ObservedObject private var progress = GuideProgress.shared

    var body: some View {
        List {
            Section {
                progressHeader
            }

            Section {
                ForEach(firstWeek) { b in
                    row(b)
                }
            } header: {
                Text("第一周认完这些")
            } footer: {
                Text("勾上的只是「我认得这个键了」，不代表会用。会用靠拍出来。")
            }

            Section {
                ForEach(later) { b in
                    row(b)
                }
            } header: {
                Text("第二周以后再学")
            } footer: {
                Text("这些不影响第一周出片，先放着。")
            }

            Section {
                Button(role: .destructive) {
                    progress.reset()
                } label: {
                    Text("清空勾选")
                }
                .disabled(progress.done.isEmpty)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("上手清单")
        .navigationBarTitleDisplayMode(.large)
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(firstWeekDone)")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                Text("/ \(firstWeek.count)")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Spacer()
                if firstWeekDone == firstWeek.count && !firstWeek.isEmpty {
                    Badge(text: "认全了", color: .green)
                }
            }
            ProgressView(value: Double(firstWeekDone),
                         total: Double(max(firstWeek.count, 1)))
        }
        .padding(.vertical, 4)
    }

    private func row(_ b: ButtonInfo) -> some View {
        let done = progress.isDone(b.id)
        return HStack(alignment: .top, spacing: 12) {
            Button {
                progress.toggle(b.id)
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(done ? Color.green : Color.secondary.opacity(0.5))
            }
            .buttonStyle(.plain)

            NavigationLink {
                ButtonDetailView(button: b,
                                 levelText: data.levels[b.level],
                                 ptpLevelText: data.ptpObservableLevels[b.ptpObservable.level])
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(b.name)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Text(b.location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: - 取值

    private var firstWeek: [ButtonInfo] {
        data.buttons.filter { $0.level == "week1" }
    }

    private var later: [ButtonInfo] {
        data.buttons.filter { $0.level != "week1" }
    }

    private var firstWeekDone: Int {
        progress.doneCount(among: firstWeek.map { $0.id })
    }
}
