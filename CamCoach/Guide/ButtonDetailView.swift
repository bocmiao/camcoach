// SPDX-License-Identifier: Apache-2.0
import SwiftUI

/// 一个按钮的完整说明。
///
/// 字段是照新手会问的顺序排的：先认位置，再问默认值，然后才讲作用和怎么用，
/// 最后放「容易搞错」。跳过顺序直接从「作用」讲起，对完全没见过相机的人不成立。
struct ButtonDetailView: View {

    let button: ButtonInfo
    let levelText: String?
    let ptpLevelText: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(button.name)
                            .font(.title3.weight(.semibold))
                        if let t = levelText {
                            Badge(text: t, color: button.level == "week1" ? .orange : .secondary)
                        }
                    }
                    if !button.aliases.isEmpty {
                        Text("也叫：" + button.aliases.joined(separator: "、"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }

            Section("它在哪") {
                Text(button.location)
            }

            Section("默认是什么") {
                Text(button.defaultText)
            }

            Section("起什么作用") {
                Text(button.whatItDoes)
            }

            Section("怎么用") {
                Text(button.howToUse)
            }

            Section("为什么重要") {
                Text(button.whyItMatters)
            }

            Section("要改成别的吗") {
                Text(button.changeIt)
            }

            Section("容易搞错的地方") {
                Text(button.misconception)
            }

            Section {
                HStack(spacing: 8) {
                    Badge(text: readableTitle, color: readableColor)
                    Spacer()
                }
                if let prop = button.ptpObservable.property, !prop.isEmpty {
                    LabeledContent("对应属性", value: prop)
                }
                Text(button.ptpObservable.note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("能不能从相机读到")
            } footer: {
                if let t = ptpLevelText {
                    Text(t)
                }
            }
        }
        .navigationTitle(button.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var readableTitle: String {
        switch button.ptpObservable.level {
        case "full": return "能稳定读到"
        case "partial": return "有时能读到"
        case "none": return "读不到"
        default: return button.ptpObservable.level
        }
    }

    private var readableColor: Color {
        switch button.ptpObservable.level {
        case "full": return .green
        case "partial": return .orange
        default: return .secondary
        }
    }
}

/// 小标签。列表里用得多，单独抽出来。
struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

/// 图鉴页下面那张简要卡：名字、一句话、进详情的入口。
struct ButtonSummaryCard: View {

    let button: ButtonInfo
    let levelText: String?
    let ptpLevelText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(button.name)
                    .font(.headline)
                if let t = levelText {
                    Badge(text: t, color: button.level == "week1" ? .orange : .secondary)
                }
                Spacer()
            }

            Text(button.whatItDoes)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            NavigationLink {
                ButtonDetailView(button: button,
                                 levelText: levelText,
                                 ptpLevelText: ptpLevelText)
            } label: {
                HStack(spacing: 4) {
                    Text("看详细")
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                }
                .font(.subheadline.weight(.medium))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
