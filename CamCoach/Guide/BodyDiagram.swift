// SPDX-License-Identifier: Apache-2.0
import SwiftUI

/// 机身示意图的配色。
///
/// 刻意不跟随界面主题：这里画的是「一台深灰色相机」，不是界面元素。
/// 浅色模式下如果机身变白，反而认不出是相机。
enum DiagramPalette {
    static let bodyHi = Color(white: 0.30)
    static let bodyLo = Color(white: 0.13)
    static let edge = Color(white: 0.58).opacity(0.30)

    static let knobHi = Color(white: 0.42)
    static let knobLo = Color(white: 0.17)

    static let inset = Color(white: 0.07)
    static let insetEdge = Color(white: 0.31).opacity(0.62)

    static let metalHi = Color(white: 0.56)
    static let metalLo = Color(white: 0.30)

    static let text = Color(white: 0.95)
    static let subtle = Color(white: 0.58)
    static let index = Color(red: 0.78, green: 0.24, blue: 0.24)
}

/// 机身示意图 + 可点热区。
///
/// 坐标写在 336×280 的设计画布上，绘制时统一乘 scale。
/// 不用 scaleEffect：它在 ScrollView 里拿不到确定高度，容易塌成 0。
///
/// 热区默认完全透明，只有选中时才浮出色块和名字。否则一台机身上二十多个
/// 半透明白圈，看起来像一堆杂点，也盖住了机身本身。
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
                    hotspot(b, s: s)
                }
            }
            .frame(width: designW * s, height: designH * s, alignment: .topLeading)
            .offset(x: ox, y: oy)
        }
        .frame(height: designH)
    }

    private func scale(for size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 1 }
        return min(size.width / designW, size.height / designH)
    }

    // MARK: - 机身轮廓

    @ViewBuilder
    private func outline(_ s: CGFloat) -> some View {
        switch viewInfo.id {
        case "top": topView(s)
        case "back": backView(s)
        case "front": frontView(s)
        case "left": leftView(s)
        case "right": rightView(s)
        default: EmptyView()
        }
    }

    private func topView(_ s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            body(24, 70, 288, 150, 10, s)

            // 背面朝下，所以取景器眼罩在俯视图里是底部突出来的一条
            panel(116, 198, 104, 24, 7, s, hi: 0.07, lo: 0.07,
                  strokeOpacity: 0.30, shadowOpacity: 0.26)

            // 热靴：金属方槽
            panel(150, 78, 42, 22, 4, s, hi: 0.56, lo: 0.30,
                  strokeOpacity: 0.20, shadowOpacity: 0)

            micGrid(200, 76, s)

            knob(74, 125, 32, s, label: "P A S M")
            knob(74, 185, 14, s)
            knob(226, 108, 15, s)
            knob(226, 152, 12, s, label: "C2")
            knob(226, 184, 12, s)

            // 电源拨杆
            panel(250, 101, 26, 8, 4, s, hi: 0.42, lo: 0.17,
                  strokeOpacity: 0.12, shadowOpacity: 0.30)

            dial(278, 92, 9, 40, 4, s)
            dial(278, 145, 9, 40, 4, s)
            dial(296, 150, 7, 30, 3, s)

            caption("顶部 · 示意图非等比", x: 168, y: 250, s)
        }
    }

    private func backView(_ s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            body(34, 36, 268, 212, 10, s)

            // 取景器壳体（比机身亮一档，浮在上面）+ 黑色眼罩
            panel(118, 16, 100, 34, 7, s, hi: 0.30, lo: 0.13,
                  strokeOpacity: 0.26, shadowOpacity: 0.30)
            panel(114, 32, 108, 36, 6, s, hi: 0.07, lo: 0.07,
                  strokeOpacity: 0.31, shadowOpacity: 0)

            // 屏幕
            panel(112, 96, 112, 104, 4, s, hi: 0.07, lo: 0.07,
                  strokeOpacity: 0.31, shadowOpacity: 0)
            LinearGradient(colors: [Color.white.opacity(0.07), .clear],
                           startPoint: .top, endPoint: .center)
                .frame(width: 112 * s, height: 104 * s)
                .clipShape(RoundedRectangle(cornerRadius: 4 * s))
                .offset(x: 112 * s, y: 96 * s)

            knob(62, 86, 17, s, label: "C3")
            knob(62, 126, 17, s, label: "M")
            knob(250, 78, 16, s, label: "C1")
            knob(270, 112, 16, s)
            knob(270, 146, 16, s)
            knob(270, 180, 16, s)
            knob(270, 214, 16, s)
            knob(170, 204, 16, s)
            knob(170, 232, 15, s)

            caption("背面 · C1 只在这一面", x: 168, y: 258, s)
        }
    }

    private func frontView(_ s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            body(34, 36, 268, 212, 10, s)

            // 握把：和机身同色系，只靠一道压痕分界
            panel(240, 54, 70, 188, 16, s, hi: 0.32, lo: 0.16,
                  strokeOpacity: 0, shadowOpacity: 0)
            crease(x: 242, from: 58, to: 238, s)

            // 卡口：金属环 → 内环 → 开口 → 三只卡口爪 → 镜膛
            disc(168, 140, 58, s, fill: AnyShapeStyle(LinearGradient(
                colors: [Color(white: 0.26), Color(white: 0.20)],
                startPoint: .top, endPoint: .bottom)),
                 strokeOpacity: 0.22, shadowOpacity: 0.26)
            disc(168, 140, 50, s, fill: AnyShapeStyle(LinearGradient(
                colors: [Color(white: 0.18), Color(white: 0.14)],
                startPoint: .top, endPoint: .bottom)),
                 strokeOpacity: 0.09, shadowOpacity: 0)
            disc(168, 140, 44, s, fill: AnyShapeStyle(DiagramPalette.inset),
                 strokeOpacity: 0.27, shadowOpacity: 0)
            bayonetTabs(s)
            disc(168, 140, 26, s, fill: AnyShapeStyle(RadialGradient(
                colors: [Color(white: 0.18), Color(white: 0.05)],
                center: .center, startRadius: 0, endRadius: 26 * s)),
                 strokeOpacity: 0.27, shadowOpacity: 0)

            // 卡口环上的红色定位点
            Circle()
                .fill(DiagramPalette.index)
                .frame(width: 8 * s, height: 8 * s)
                .offset(x: 164 * s, y: 80 * s)

            knob(96, 150, 15, s)

            caption("正面 · 镜头卡口", x: 168, y: 258, s)
        }
    }

    private func leftView(_ s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            body(93, 56, 150, 176, 12, s)
            lug(162, 50, s)

            // 接口盖
            panel(106, 100, 124, 88, 8, s, hi: 0.34, lo: 0.18,
                  strokeOpacity: 0.30, shadowOpacity: 0.24)
            crease(x: 110, from: 104, to: 184, s)

            // USB-C：圆角矩形，不是圆
            panel(153, 144, 30, 12, 6, s, hi: 0.07, lo: 0.07,
                  strokeOpacity: 0.33, shadowOpacity: 0)

            caption("左侧 · 接口盖里", x: 168, y: 258, s)
        }
    }

    private func rightView(_ s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            body(93, 56, 150, 176, 12, s)
            lug(162, 50, s)

            // 卡槽盖
            panel(104, 74, 128, 140, 8, s, hi: 0.34, lo: 0.18,
                  strokeOpacity: 0.30, shadowOpacity: 0.24)
            crease(x: 228, from: 78, to: 210, s)

            cardSlot(150, 102, s)
            cardSlot(150, 166, s)

            caption("右侧 · 卡槽盖里", x: 168, y: 258, s)
        }
    }

    // MARK: - 热区

    @ViewBuilder
    private func hotspot(_ b: ButtonInfo, s: CGFloat) -> some View {
        let on = (selectedID == b.id)

        if let c = b.hotspot.circle {
            Circle()
                .fill(on ? Color.accentColor.opacity(0.22) : Color.clear)
                .frame(width: c.r * 2 * s, height: c.r * 2 * s)
                .overlay(
                    Circle().stroke(on ? Color.accentColor : Color.clear,
                                    lineWidth: 2)
                )
                .contentShape(Circle())
                .offset(x: (c.cx - c.r) * s, y: (c.cy - c.r) * s)
                .onTapGesture { onTap(b) }

            if on {
                tag(b.name,
                    atX: c.cx * s,
                    atY: (c.cy - c.r - 11) * s,
                    below: (c.cy - c.r) * s < 18,
                    s: s)
            }
        } else if let r = b.hotspot.rect {
            RoundedRectangle(cornerRadius: 5 * s)
                .fill(on ? Color.accentColor.opacity(0.22) : Color.clear)
                .frame(width: r.w * s, height: r.h * s)
                .overlay(
                    RoundedRectangle(cornerRadius: 5 * s)
                        .stroke(on ? Color.accentColor : Color.clear, lineWidth: 2)
                )
                .contentShape(Rectangle())
                .offset(x: r.x * s, y: r.y * s)
                .onTapGesture { onTap(b) }

            if on {
                tag(b.name,
                    atX: (r.x + r.w / 2) * s,
                    atY: (r.y - 11) * s,
                    below: r.y * s < 18,
                    s: s)
            }
        }
    }

    /// 选中时浮在热区上方的名字。用 position 而不是 offset：
    /// 标签不需要响应点击，占满父容器也无所谓，反而能精确居中。
    private func tag(_ text: String, atX x: CGFloat, atY y: CGFloat,
                     below: Bool, s: CGFloat) -> some View {
        Text(text)
            .font(.system(size: max(8, 9 * s), weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6 * s)
            .padding(.vertical, 2.5 * s)
            .background(Capsule().fill(Color.accentColor))
            .shadow(color: .black.opacity(0.25), radius: 2 * s, y: 1 * s)
            .position(x: x, y: below ? y + 22 * s : y)
            .allowsHitTesting(false)
    }

    // MARK: - 图元

    private func body(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
                      _ radius: CGFloat, _ s: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius * s)
            .fill(LinearGradient(colors: [DiagramPalette.bodyHi, DiagramPalette.bodyLo],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: w * s, height: h * s)
            .overlay(
                RoundedRectangle(cornerRadius: radius * s)
                    .strokeBorder(DiagramPalette.edge, lineWidth: max(0.5, 0.8 * s))
            )
            .shadow(color: .black.opacity(0.28), radius: 7 * s, x: 0, y: 4 * s)
            .offset(x: x * s, y: y * s)
    }

    /// 平涂的圆角块：热靴、接口盖、卡槽盖、握把这些，上下渐变就够。
    private func panel(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
                       _ radius: CGFloat, _ s: CGFloat,
                       hi: Double, lo: Double,
                       strokeOpacity: Double, shadowOpacity: Double) -> some View {
        RoundedRectangle(cornerRadius: radius * s)
            .fill(LinearGradient(colors: [Color(white: hi), Color(white: lo)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: w * s, height: h * s)
            .overlay(
                RoundedRectangle(cornerRadius: radius * s)
                    .strokeBorder(Color.white.opacity(strokeOpacity),
                                  lineWidth: max(0.5, 0.7 * s))
            )
            .shadow(color: .black.opacity(shadowOpacity),
                    radius: shadowOpacity > 0 ? 4 * s : 0, x: 0, y: 3 * s)
            .offset(x: x * s, y: y * s)
    }

    private func disc(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ s: CGFloat,
                      fill: AnyShapeStyle,
                      strokeOpacity: Double, shadowOpacity: Double) -> some View {
        Circle()
            .fill(fill)
            .overlay(
                Circle().strokeBorder(Color.white.opacity(strokeOpacity),
                                      lineWidth: max(0.5, 0.7 * s))
            )
            .frame(width: r * 2 * s, height: r * 2 * s)
            .shadow(color: .black.opacity(shadowOpacity),
                    radius: shadowOpacity > 0 ? 3 * s : 0, x: 0, y: 1.6 * s)
            .offset(x: (cx - r) * s, y: (cy - r) * s)
    }

    /// 圆形按键或转盘。左上角打光，右下压暗，看起来是个实体。
    private func knob(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat,
                      _ s: CGFloat, label: String? = nil) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [DiagramPalette.knobHi, DiagramPalette.knobLo],
                                     center: UnitPoint(x: 0.34, y: 0.28),
                                     startRadius: 0, endRadius: r * 2.1 * s))
                .overlay(
                    Circle().strokeBorder(Color.white.opacity(0.14),
                                          lineWidth: max(0.5, 0.7 * s))
                )
            if let label = label {
                // 字号不按半径算：C2 那种 r=10 的圆按比例会掉到 3pt，
                // 完全看不见。统一一个能读的下限，靠 minimumScaleFactor 兜住长的。
                Text(label)
                    .font(.system(size: max(6.5, 7.5 * s), weight: .medium))
                    .foregroundStyle(DiagramPalette.text)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.horizontal, 1.5 * s)
            }
        }
        .frame(width: r * 2 * s, height: r * 2 * s)
        .shadow(color: .black.opacity(0.32), radius: 2 * s, x: 0, y: 1.2 * s)
        .offset(x: (cx - r) * s, y: (cy - r) * s)
    }

    /// 卡口里的三只爪。半径 38，按 90° / 210° / 330° 算好的坐标直接写死，
    /// 结构体里没必要为一个静态位置引入三角函数。
    private func bayonetTabs(_ s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            tab(168, 102, s)
            tab(135, 159, s)
            tab(201, 159, s)
        }
    }

    private func tab(_ cx: CGFloat, _ cy: CGFloat, _ s: CGFloat) -> some View {
        Circle()
            .fill(LinearGradient(colors: [Color(white: 0.66), Color(white: 0.49)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: 8 * s, height: 8 * s)
            .offset(x: (cx - 4) * s, y: (cy - 4) * s)
    }

    /// 拨轮：竖着的胶囊。
    private func dial(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
                      _ radius: CGFloat, _ s: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius * s)
            .fill(LinearGradient(colors: [DiagramPalette.knobHi, DiagramPalette.knobLo],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(width: w * s, height: h * s)
            .overlay(
                RoundedRectangle(cornerRadius: radius * s)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: max(0.5, 0.7 * s))
            )
            .shadow(color: .black.opacity(0.3), radius: 1.5 * s, x: 0, y: 1 * s)
            .offset(x: x * s, y: y * s)
    }

    /// 麦克风阵列。两排小孔，比一整块灰面更像机器。
    private func micGrid(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<2, id: \.self) { row in
                ForEach(0..<6, id: \.self) { col in
                    Circle()
                        .fill(Color(white: 0.09))
                        .frame(width: 3 * s, height: 3 * s)
                        .offset(x: (x + CGFloat(col) * 9) * s,
                                y: (y + CGFloat(row) * 7) * s)
                }
            }
        }
    }

    /// 盖板之间的压痕。一比一像素，缩放后至少留 1pt，不然会消失。
    private func crease(x: CGFloat, from y0: CGFloat, to y1: CGFloat,
                        _ s: CGFloat) -> some View {
        Rectangle()
            .fill(Color(white: 0.09))
            .frame(width: max(1, 1 * s), height: (y1 - y0) * s)
            .offset(x: x * s, y: y0 * s)
    }

    private func lug(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat) -> some View {
        panel(x, y, 11, 10, 3, s, hi: 0.20, lo: 0.10,
              strokeOpacity: 0.24, shadowOpacity: 0)
    }

    private func cardSlot(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat) -> some View {
        panel(x, y, 36, 30, 4, s, hi: 0.07, lo: 0.07,
              strokeOpacity: 0.33, shadowOpacity: 0)
    }

    private func caption(_ text: String, x: CGFloat, y: CGFloat, _ s: CGFloat) -> some View {
        Text(text)
            .font(.system(size: max(8, 10 * s)))
            .foregroundStyle(DiagramPalette.subtle)
            .frame(width: 240 * s, height: 14 * s)
            .offset(x: (x - 120) * s, y: (y - 7) * s)
    }
}
