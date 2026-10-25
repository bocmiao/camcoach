// SPDX-License-Identifier: Apache-2.0
import SwiftUI

/// 图鉴首页：选一个视角，点机身上的圆点。
///
/// 页面结构是「视角 → 机身图 → 当前选中 → 这一面的全部按键」。
/// 列表和机身图双向联动，因为有人习惯直接点图，也有人喜欢从列表里找名字。
struct BodyDiagramView: View {

    let data: CameraData

    @State private var viewID: String
    @State private var selectedID: String?

    init(data: CameraData) {
        self.data = data
        _viewID = State(initialValue: data.views.first?.id ?? "top")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                deviceLabel
                picker
                diagramCard
                if let b = selectedButton {
                    ButtonSummaryCard(button: b,
                                      levelText: levelText(for: b),
                                      ptpLevelText: ptpLevelText(for: b))
                }
                buttonList
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("看按键")
        .navigationBarTitleDisplayMode(.large)
    }

    /// 机型与固件基线。菜单和键位会随固件变，先说明白这页是按哪版写的。
    private var deviceLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "camera")
                .font(.caption2)
            Text(data.device.shortLabel)
                .font(.caption)
            Spacer()
        }
        .foregroundStyle(.secondary)
    }

    // MARK: - 视角

    private var picker: some View {
        // 用自定义 Binding 而不是 onChange：onChange 的单参数版本在
        // iOS 17 SDK 下会报废弃警告，两参数版本又要求 iOS 17，部署目标是 16。
        Picker("视角", selection: Binding(
            get: { viewID },
            set: { newValue in
                viewID = newValue
                selectedID = nil
            }
        )) {
            ForEach(data.views) { v in
                Text(v.name).tag(v.id)
            }
        }
        .pickerStyle(.segmented)
    }

    private var diagramCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            BodyDiagram(viewInfo: currentView,
                        buttons: currentButtons,
                        selectedID: selectedID) { b in
                selectedID = (selectedID == b.id) ? nil : b.id
            }
            Text(currentView.hint)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 列表

    private var buttonList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("这一面有 \(currentButtons.count) 个键")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

            ForEach(currentButtons) { b in
                Button {
                    selectedID = (selectedID == b.id) ? nil : b.id
                } label: {
                    row(b)
                }
                .buttonStyle(.plain)

                if b.id != currentButtons.last?.id {
                    Divider().padding(.leading, 18)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func row(_ b: ButtonInfo) -> some View {
        let on = (selectedID == b.id)
        return HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(on ? Color.accentColor : Color.secondary.opacity(0.35))
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(b.name)
                        .font(.subheadline.weight(on ? .semibold : .regular))
                        .foregroundStyle(.primary)
                    if b.level == "week1" {
                        Badge(text: "第一周", color: .orange)
                    }
                    Spacer(minLength: 0)
                }
                if on {
                    Text(b.whatItDoes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    // MARK: - 取值

    private var currentView: BodyViewInfo {
        data.view(withID: viewID)
            ?? data.views.first
            ?? BodyViewInfo(id: "top", name: "顶部", hint: "")
    }

    private var currentButtons: [ButtonInfo] {
        data.buttonsFor(view: viewID)
    }

    private var selectedButton: ButtonInfo? {
        guard let id = selectedID else { return nil }
        return data.buttons.first { $0.id == id }
    }

    private func levelText(for b: ButtonInfo) -> String? {
        data.levels[b.level]
    }

    private func ptpLevelText(for b: ButtonInfo) -> String? {
        data.ptpObservableLevels[b.ptpObservable.level]
    }
}
