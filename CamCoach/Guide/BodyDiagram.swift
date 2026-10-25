// SPDX-License-Identifier: Apache-2.0
import SwiftUI

/// 机身示意图的配色。跟相机本身的颜色走，不跟随界面主题，
/// 因为这是「画一台相机」，不是界面元素。
enum DiagramPalette {
    static let body = Color(red: 0.20, green: 0.20, blue: 0.185)
    static let part = Color(red: 0.29, green: 0.29, blue: 0.27)
    static let line = Color(red: 0.37, green: 0.37, blue: 0.38)
    static let screen = Color(red: 0.15, green: 0.15, blue: 0.14)
    static let caption = Color(red: 0.42, green: 0.42, blue: 0.39)
    static let label = Color(red: 0.91, green: 0.90, blue: 0.87)
}

/// 机身示意图 + 可点热区。
///
/// 坐标全部写在 336×280 的设计画布上，绘制时统一乘 scale。
/// 没用 scaleEffect：它在 ScrollView 里拿不到确定高度，容易塌成 0；
/// 手动乘比例虽然啰嗦，但布局尺寸是实的，热区位置也不会偏。
struct BodyDiagram: View {

    let viewInfo: BodyViewInfo
    let buttons: [ButtonInfo]
    let selectedID: String?
    let onTap: (ButtonInfo) -> Void

    private let designW: CGFloat = 336
    private let designH: CGFloat = 280

    var body: some View {
        GeometryReader { geo in
            let s = scale(for: geo.size)
            let ox = (geo.size.width - designW * s) / 2
            let oy = (geo.size.height - designH * s) / 2

            ZStack(alignment: .topLeading) {
                outline(s)
                ForEach(buttons) { b in
                    hotspotView(b, s: s)
                }
            }
            .offset(x: ox, y: oy)
        }
        // 给一个确定高度，ScrollView 里的 GeometryReader 才有得算。
        // 280 是设计稿原高，宽屏时图按宽度撑满，窄屏时上下留一点空。
        .frame(height: designH)
    }

    private func scale(for size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 1 }
        return min(size.width / designW, size.height / designH)
    }

    // MARK: - 各视角的机身轮廓

    @ViewBuilder
    private func outline(_ s: CGFloat) -> some View {
        switch viewInfo.id {
        case "top": topOutline(s)
        case "back": backOutline(s)
        case "front": frontOutline(s)
        case "left": leftOutline(s)
        case "right": rightOutline(s)
        default: EmptyView()
        }
    }

    private func topOutline(_ s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            box(24, 70, 288, 150, 10, DiagramPalette.body, s)
            box(150, 78, 42, 22, 4, DiagramPalette.part, s)      // 热靴
            disc(74, 125, 32, DiagramPalette.part, s)            // 模式盘
            disc(74, 185, 12, DiagramPalette.line, s)            // S&Q
            disc(226, 108, 13, DiagramPalette.line, s)           // 快门
            box(250, 101, 26, 8, 4, DiagramPalette.line, s)      // 电源拨杆
            disc(226, 152, 10, DiagramPalette.part, s)           // C2
            disc(226, 184, 10, DiagramPalette.part, s)           // MOVIE
            box(278, 92, 9, 40, 4, DiagramPalette.line, s)       // 前转盘
            box(278, 145, 9, 40, 4, DiagramPalette.line, s)      // 后转盘 L
            box(296, 150, 7, 30, 3, DiagramPalette.line, s)      // 后转盘 R
            caption("P A S M", x: 74, y: 124, s, size: 10)
            caption("顶部 · 示意图非等比", x: 168, y: 250, s)
        }
    }

    private func backOutline(_ s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            box(34, 36, 268, 212, 10, DiagramPalette.body, s)
            box(106, 44, 124, 40, 4, DiagramPalette.part, s)     // 取景器
            box(112, 96, 112, 104, 4, DiagramPalette.screen, s)  // 屏幕
            disc(62, 86, 16, DiagramPalette.line, s)             // C3
            disc(62, 126, 16, DiagramPalette.line, s)            // MENU
            disc(250, 78, 16, DiagramPalette.line, s)            // C1
            disc(270, 112, 16, DiagramPalette.line, s)           // AF-ON
            disc(270, 146, 16, DiagramPalette.line, s)           // AEL
            disc(270, 180, 16, DiagramPalette.line, s)           // Fn
            disc(270, 214, 16, DiagramPalette.line, s)           // 播放
            disc(170, 204, 16, DiagramPalette.line, s)           // 摇杆
            disc(170, 232, 15, DiagramPalette.line, s)           // 控制拨轮
            caption("C3", x: 62, y: 86, s, size: 9, color: DiagramPalette.label)
            caption("MENU", x: 62, y: 126, s, size: 8, color: DiagramPalette.label)
            caption("C1", x: 250, y: 78, s, size: 9, color: DiagramPalette.label)
            caption("背面 · C1 只在这一面", x: 168, y: 258, s)
        }
    }

    private func frontOutline(_ s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            box(34, 36, 268, 212, 10, DiagramPalette.body, s)
            disc(168, 140, 58, DiagramPalette.line, s)           // 卡口外圈
            disc(168, 140, 46, DiagramPalette.screen, s)         // 卡口内圈
            disc(168, 140, 26, DiagramPalette.part, s)           // 传感器示意
            disc(96, 150, 15, DiagramPalette.part, s)            // 镜头释放
            caption("正面 · 卡口", x: 168, y: 258, s)
        }
    }

    private func leftOutline(_ s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            box(34, 60, 268, 160, 10, DiagramPalette.body, s)
            box(120, 110, 96, 60, 6, DiagramPalette.part, s)     // 接口盖
            disc(168, 150, 22, DiagramPalette.screen, s)         // USB-C
            caption("左侧 · 接口盖里", x: 168, y: 258, s)
        }
    }

    private func rightOutline(_ s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            box(34, 60, 268, 160, 10, DiagramPalette.body, s)
            box(130, 80, 76, 120, 6, DiagramPalette.part, s)     // 卡槽盖
            disc(168, 116, 23, DiagramPalette.screen, s)         // 卡槽 1
            disc(168, 180, 23, DiagramPalette.screen, s)         // 卡槽 2
            caption("右侧 · 卡槽盖里", x: 168, y: 258, s)
        }
    }

    // MARK: - 热区

    @ViewBuilder
    private func hotspotView(_ b: ButtonInfo, s: CGFloat) -> some View {
        let on = (selectedID == b.id)
        if let c = b.hotspot.circle {
            Circle()
                .fill(hitFill(on))
                .frame(width: c.r * 2 * s, height: c.r * 2 * s)
                .overlay(Circle().stroke(hitStroke(on), lineWidth: on ? 2 : 1))
                .contentShape(Circle())
                .offset(x: (c.cx - c.r) * s, y: (c.cy - c.r) * s)
                .onTapGesture { onTap(b) }
        } else if let r = b.hotspot.rect {
            RoundedRectangle(cornerRadius: 5 * s)
                .fill(hitFill(on))
                .frame(width: r.w * s, height: r.h * s)
                .overlay(
                    RoundedRectangle(cornerRadius: 5 * s)
                        .stroke(hitStroke(on), lineWidth: on ? 2 : 1)
                )
                .contentShape(Rectangle())
                .offset(x: r.x * s, y: r.y * s)
                .onTapGesture { onTap(b) }
        }
    }

    private func hitFill(_ selected: Bool) -> Color {
        Color.accentColor.opacity(selected ? 0.45 : 0.14)
    }

    private func hitStroke(_ selected: Bool) -> Color {
        selected ? Color.accentColor : Color.accentColor.opacity(0.5)
    }

    // MARK: - 画图元

    /// ZStack 是 topLeading 对齐的，所以这里用 offset 而不是 position：
    /// position 会让视图占满父容器，多个热区叠在一起就分不清谁响应点击。
    private func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
                     _ radius: CGFloat, _ fill: Color, _ s: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius * s)
            .fill(fill)
            .frame(width: w * s, height: h * s)
            .overlay(
                RoundedRectangle(cornerRadius: radius * s)
                    .stroke(DiagramPalette.line, lineWidth: 0.5)
            )
            .offset(x: x * s, y: y * s)
    }

    private func disc(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat,
                      _ fill: Color, _ s: CGFloat) -> some View {
        Circle()
            .fill(fill)
            .frame(width: r * 2 * s, height: r * 2 * s)
            .overlay(Circle().stroke(DiagramPalette.line, lineWidth: 0.5))
            .offset(x: (cx - r) * s, y: (cy - r) * s)
    }

    private func caption(_ text: String, x: CGFloat, y: CGFloat,
                         _ s: CGFloat, size: CGFloat = 10,
                         color: Color = DiagramPalette.caption) -> some View {
        Text(text)
            .font(.system(size: size * s))
            .foregroundStyle(color)
            .frame(width: 200 * s)
            .offset(x: (x - 100) * s, y: (y - size / 2) * s)
    }
}
