// SPDX-License-Identifier: Apache-2.0
import SwiftUI

/// 预设：从「我想拍成什么样」倒推参数。
///
/// 参数行用等宽字体，因为它是拿来照着在相机上拨的，字距清楚比好看重要。
struct PresetListView: View {

    let data: CameraData

    @State private var expanded: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("先在相机上拨好参数，再拍。每一组下面的步骤就是照着念的顺序。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 2)

                ForEach(data.presets) { p in
                    card(p)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("拍什么")
        .navigationBarTitleDisplayMode(.large)
    }

    private func card(_ p: ShootingPreset) -> some View {
        let on = (expanded == p.id)

        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(p.name)
                    .font(.headline)
                Text(p.desc)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(p.params)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Label(p.warn, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
                .labelStyle(.titleAndIcon)

            if on {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(p.steps.enumerated()), id: \.offset) { idx, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(idx + 1)")
                                .font(.caption2.weight(.semibold))
                                .frame(width: 16, height: 16)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(Circle())
                            Text(step)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 2)
            }

            Button {
                expanded = on ? nil : p.id
            } label: {
                HStack(spacing: 4) {
                    Text(on ? "收起步骤" : "照着拨，\(p.steps.count) 步")
                    Image(systemName: on ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
