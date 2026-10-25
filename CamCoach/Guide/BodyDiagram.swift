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
/// 画布固定 336×280，和网页原型用同一套坐标，最后整体缩放，
/// 这样热区坐标只需要维护一份，视图里不用到处乘比例。
struct BodyDiagram: View {

    let viewInfo: BodyViewInfo
    let buttons: [ButtonInfo]
    let selectedID: String?
    let onTap: (ButtonInfo) -> Void

    private let canvas = CGSize(width: 336, height: 280)

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / canvas.width,
                            geo.size.height / canvas.height)
            ZStack(alignment: .topLeading) {
                outline
                ForEach(buttons) { b in
                    hotspotView(b)
                }
            }
            .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: canvas.width * scale,
                   height: canvas.height * scale,
                   alignment: .topLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .aspectRatio(canvas.width / canvas.height, contentMode: .fit)
    }

    // MARK: - 各视角的机身轮廓

    @ViewBuilder
    private var outline: some View {
        switch viewInfo.id {
        case "top": topOutline
        case "back": backOutline
        case "front": frontOutline
        case "left": leftOutline
        case "right": rightOutline
        default: EmptyView()
        }
    }

    private var topOutline: some View {
        ZStack(alignment: .topLeading) {
            box(24, 70, 288, 150, 10, DiagramPalette.body)
            box(150, 78, 42, 22, 4, DiagramPalette.part)      // 热靴
            disc(74, 125, 32, DiagramPalette.part)            // 模式盘
            disc(74, 185, 12, DiagramPalette.line)            // S&Q
            disc(226, 108, 13, DiagramPalette.line)           // 快门
            box(250, 101, 26, 8, 4, DiagramPalette.line)      // 电源拨杆
            disc(226, 152, 10, DiagramPalette.part)           // C2
            disc(226, 184, 10, DiagramPalette.part)           // MOVIE
            box(278, 92, 9, 40, 4, DiagramPalette.line)       // 前转盘
            box(278, 145, 9, 40, 4, DiagramPalette.line)      // 后转盘 L
            box(296, 150, 7, 30, 3, DiagramPalette.line)      // 后转盘 R
            caption("P A S M", x: 74, y: 124, size: 10)
            caption("顶部 · 示意图非等比", x: 168, y: 250)
        }
    }

    private var backOutline: some View {
        ZStack(alignment: .topLeading) {
            box(34, 36, 268, 212, 10, DiagramPalette.body)
            box(106, 44, 124, 40, 4, DiagramPalette.part)     // 取景器
            box(112, 96, 112, 104, 4, DiagramPalette.screen)  // 屏幕
            disc(62, 86, 16, DiagramPalette.line)             // C3
            disc(62, 126, 16, DiagramPalette.line)            // MENU
            disc(250, 78, 16, DiagramPalette.line)            // C1
            disc(270, 112, 16, DiagramPalette.line)           // AF-ON
            disc(270, 146, 16, DiagramPalette.line)           // AEL
            disc(270, 180, 16, DiagramPalette.line)           // Fn
            disc(270, 214, 16, DiagramPalette.line)           // 播放
            disc(170, 204, 16, DiagramPalette.line)           // 摇杆
            disc(170, 232, 15, DiagramPalette.line)           // 控制拨轮
            caption("C3", x: 62, y: 86, size: 9)
            caption("MENU", x: 62, y: 126, size: 8)
            caption("C1", x: 250, y: 78, size: 9)
            caption("背面 · C1 只在这一面", x: 168, y: 258)
        }
    }

    private var frontOutline: some View {
        ZStack(alignment: .topLeading) {
            box(34, 36, 268, 212, 10, DiagramPalette.body)
            disc(168, 140, 58, DiagramPalette.line)           // 卡口外圈
            disc(168, 140, 46, DiagramPalette.screen)         // 卡口内圈
            disc(168, 140, 26, DiagramPalette.part)           // 传感器示意
            disc(96, 150, 15, DiagramPalette.part)            // 镜头释放
            caption("正面 · 卡口", x: 168, y: 258)
        }
    }

    private var leftOutline: some View {
        ZStack(alignment: .topLeading) {
            box(34, 60, 268, 160, 10, DiagramPalette.body)
            box(120, 110, 96, 60, 6, DiagramPalette.part)     // 接口盖
            disc(168, 150, 22, DiagramPalette.screen)         // USB-C
            caption("左侧 · 接口盖里", x: 168, y: 258)
        }
    }

    private var rightOutline: some View {
        ZStack(alignment: .topLeading) {
            box(34, 60, 268, 160, 10, DiagramPalette.body)
            box(130, 80, 76, 120, 6, DiagramPalette.part)     // 卡槽盖
            disc(168, 116, 23, DiagramPalette.screen)         // 卡槽 1
            disc(168, 180, 23, DiagramPalette.screen)         // 卡槽 2
            caption("右侧 · 卡槽盖里", x: 168, y: 258)
        }
    }

    // MARK: - 热区

    @ViewBuilder
    private func hotspotView(_ b: ButtonInfo) -> some View {
        let on = (selectedID == b.id)
        if let c = b.hotspot.circle {
            Circle()
                .fill(hitFill(on))
                .frame(width: c.r * 2, height: c.r * 2)
                .overlay(
                    Circle().stroke(hitStroke(on), lineWidth: on ? 2 : 1)
                )
                .contentShape(Circle())
                .offset(x: c.cx - c.r, y: c.cy - c.r)
                .onTapGesture { onTap(b) }
        } else if let r = b.hotspot.rect {
            RoundedRectangle(cornerRadius: 5)
                .fill(hitFill(on))
                .frame(width: r.w, height: r.h)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(hitStroke(on), lineWidth: on ? 2 : 1)
                )
                .contentShape(Rectangle())
                .offset(x: r.x, y: r.y)
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
                     _ radius: CGFloat, _ fill: Color) -> some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(fill)
            .frame(width: w, height: h)
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(DiagramPalette.line, lineWidth: 0.5)
            )
            .offset(x: x, y: y)
    }

    private func disc(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat,
                      _ fill: Color) -> some View {
        Circle()
            .fill(fill)
            .frame(width: r * 2, height: r * 2)
            .overlay(Circle().stroke(DiagramPalette.line, lineWidth: 0.5))
            .offset(x: cx - r, y: cy - r)
    }

    private func caption(_ text: String, x: CGFloat, y: CGFloat,
                         size: CGFloat = 10) -> some View {
        Text(text)
            .font(.system(size: size))
            .foregroundStyle(DiagramPalette.caption)
            .frame(width: 200)
            .offset(x: x - 100, y: y - size / 2)
    }
}
