#!/usr/bin/env python3
"""把按钮文案和菜单索引合成一份给 iOS 用的 JSON。

`data/guide-source.json` 是按钮文案的权威来源，但它有 7 个按钮没有 hotspot
（正面 / 左侧 / 右侧三个视角当时没画）。这里按每个按钮的 location
描述补上坐标，统一用 336×280 的坐标系，再并进菜单反查、预设和连接检查。

产物：`CamCoach/Resources/camcoach-data.json`，打包进 App。

改完跑一次，别手改产物。
    python tools/build-guide-data.py
"""
import json
import pathlib

HERE = pathlib.Path(__file__).resolve().parent          # ios/tools
ROOT = HERE.parent                                       # ios
DATA = ROOT / "data"
SRC = DATA / "guide-source.json"
OUT = ROOT / "CamCoach" / "Resources" / "camcoach-data.json"

# 三个新视角的机身轮廓。front/left/right 之前是 todo，这里定下来。
VIEWS = [
    {"id": "top", "name": "顶部", "hint": "模式盘、快门、热靴、转盘都在这面"},
    {"id": "back", "name": "背面", "hint": "屏幕、菜单、对焦与曝光锁定"},
    {"id": "front", "name": "正面", "hint": "镜头卡口与释放按钮"},
    {"id": "left", "name": "左侧", "hint": "接口盖里面是 USB-C"},
    {"id": "right", "name": "右侧", "hint": "卡槽盖里面是双卡"},
]

# 补坐标的依据写在这里，改的时候能对回原文。
# play            背面右下，屏幕右侧那一列的最下面
# controlWheel    背面右侧，摇杆下方那个圆形四向键
# lensRelease     机身正面左侧，镜头卡口旁边那个圆钮
# mount           机身正面正中那个大圆环
# usbc            机身左侧，接口盖里面
# slot1 / slot2   机身右侧，卡槽盖里面靠上 / 靠下
EXTRA_HOTSPOTS = {
    "play":         {"shape": "circle", "cx": 270, "cy": 214, "r": 16},
    "controlWheel": {"shape": "circle", "cx": 170, "cy": 232, "r": 15},
    "lensRelease":  {"shape": "circle", "cx": 96,  "cy": 150, "r": 15},
    "mount":        {"shape": "circle", "cx": 168, "cy": 140, "r": 58},
    "usbc":         {"shape": "circle", "cx": 168, "cy": 150, "r": 22},
    "slot1":        {"shape": "circle", "cx": 168, "cy": 116, "r": 23},
    "slot2":        {"shape": "circle", "cx": 168, "cy": 180, "r": 23},
}

# 背面原有布局要微调：右侧列挤出第 6 个位置给播放键，
# 摇杆和控制拨轮挪到机身中下部。原来 7 个按钮的坐标保持不变。
BACK_OVERRIDE = {
    "c1":   {"shape": "circle", "cx": 250, "cy": 78,  "r": 16},
    "afon": {"shape": "circle", "cx": 270, "cy": 112, "r": 16},
    "ael":  {"shape": "circle", "cx": 270, "cy": 146, "r": 16},
    "fn":   {"shape": "circle", "cx": 270, "cy": 180, "r": 16},
    "stick": {"shape": "circle", "cx": 170, "cy": 204, "r": 16},
}

MENUS = [
    {"want": "关掉快门咔嚓声", "path": "设置 → 音频信号 → 关", "note": "很多人以为在「快门」里找"},
    {"want": "格式化存储卡", "path": "拍摄 → 媒体 → 格式化", "note": "它在「拍摄」栏，不在「设置」里"},
    {"want": "开静音快门", "path": "拍摄 → 快门/静音 → 静音拍摄", "note": "静音快门不能用闪光灯"},
    {"want": "开高光警告（斑马线）", "path": "设置 → 显示选项 → 斑马线显示", "note": "「斑马线」就是高光警告，名字对不上"},
    {"want": "S-Log 画面还原着看", "path": "设置 → 显示选项 → 伽马显示辅助", "note": "只改监看，不改文件"},
    {"want": "录长视频别过热关机", "path": "设置 → 电源设置选项 → 自动关机温度 → 高", "note": "设高之后别长时间手持"},
    {"want": "照片和视频参数分开", "path": "设置 → 操作自定义 → 静态/动态不同设置", "note": "最该先做的一步，最少人做"},
    {"want": "拍完自动回看", "path": "设置 → 显示选项 → 自动检视", "note": "出厂是关的"},
    {"want": "开构图网格线", "path": "拍摄 → 拍摄显示 → 网格线显示 → 三等分", "note": "在「拍摄」栏，不在「设置」"},
    {"want": "防止手抖拍糊", "path": "曝光/颜色 → 曝光 → ISO AUTO 最小速度 → 1/125", "note": "只对 P 档和 A 档生效"},
    {"want": "两张卡各存一份", "path": "拍摄 → 媒体 → 摄像媒体设置 → 同时记录", "note": "默认不是同时记录"},
    {"want": "把常用项提到第一层", "path": "MENU → 我的菜单", "note": "可以把 7 项常用设置放进去"},
]

PRESETS = [
    {
        "name": "背景虚化的人像",
        "desc": "人清楚，背景糊成一团",
        "params": "A 档 · f/1.8 · ISO AUTO≤3200 · 快门≥1/125 · AF-C + 人眼 · PT",
        "warn": "光线很暗时会糊，换「夜里也能拍清」。",
        "steps": ["档位 → A", "光圈 → f/1.8", "ISO → AUTO，上限 3200",
                  "快门下限 → 1/125", "对焦 → AF-C + 人眼", "创意外观 → PT"],
    },
    {
        "name": "凝固跑动的娃 / 宠物",
        "desc": "它在跑，也要拍清楚",
        "params": "S 档 · 1/500 · ISO AUTO≤6400 · AF-C · 广域跟踪",
        "warn": "光线不够时 ISO 会飙到 6400 以上，噪点明显。",
        "steps": ["档位 → S", "快门 → 1/500", "ISO → AUTO，上限 6400",
                  "对焦 → AF-C", "区域 → 广域跟踪", "驱动 → 连拍 Hi"],
    },
    {
        "name": "前后都清楚的风光",
        "desc": "从脚下到远山，全都清楚",
        "params": "A 档 · f/8 · ISO 100 · 快门≥1/125 · AF-S 单点 · 5500K",
        "warn": "手持时快门可能不够，最好上脚架。",
        "steps": ["档位 → A", "光圈 → f/8", "ISO → 100", "快门下限 → 1/125",
                  "对焦 → AF-S 单点", "白平衡 → 5500K"],
    },
    {
        "name": "手机能直接发的视频",
        "desc": "拍完不用调色就能发",
        "params": "视频档 · 4K30p 全画幅 · PP11 · 1/60 · f/2.8",
        "warn": "只有 4K30p 是全画幅，4K60 会裁切变窄。",
        "steps": ["切到视频档", "记录格式 → 4K 30p", "图片配置文件 → PP11",
                  "快门 → 1/60", "对焦 → AF-C 人眼", "防抖 → 标准"],
    },
    {
        "name": "夜里也能拍清",
        "desc": "天黑，但不想拍成一团糊",
        "params": "A 档 · f/1.8 · ISO AUTO≤6400 · 快门≥1/60 · AF-S 单点",
        "warn": "人在动的话还是会糊，这是物理限制。",
        "steps": ["档位 → A", "光圈 → f/1.8", "ISO → AUTO，上限 6400",
                  "快门下限 → 1/60", "对焦 → AF-S 单点", "白平衡 → 3800K"],
    },
]

CONNECT_CHECKS = [
    {"title": "把相机 USB 模式改成「遥控拍摄」", "detail": "MENU → 设置 → USB → USB 连接模式 → 遥控拍摄"},
    {"title": "卡槽里已经插了存储卡", "detail": "没卡时相机不会进入遥控状态，这是硬条件"},
    {"title": "退出 Creators' App 或 Imaging Edge", "detail": "它们会抢占遥控通道，开了就连不上"},
    {"title": "确认用的是数据线", "detail": "随机附赠的充电线不行，要能传数据的"},
    {"title": "关掉相机的 USB 供电", "detail": "开着会向手机取电，过流保护会让连接几秒就断"},
    {"title": "手机已经解锁", "detail": "iOS 的「有线配件」默认是解锁后才允许"},
]


def main():
    raw = json.loads(SRC.read_text(encoding="utf-8"))
    buttons = []
    added = 0
    for b in raw["buttons"]:
        b = dict(b)
        if b["id"] in EXTRA_HOTSPOTS:
            b["hotspot"] = EXTRA_HOTSPOTS[b["id"]]
            added += 1
        elif b["id"] in BACK_OVERRIDE:
            b["hotspot"] = BACK_OVERRIDE[b["id"]]
        buttons.append(b)

    order = {v["id"]: i for i, v in enumerate(VIEWS)}
    buttons.sort(key=lambda b: (order.get(b["view"], 99), b["id"]))

    out = {
        "schemaVersion": 1,
        "device": raw.get("device", "ILCE-7M4"),
        "views": VIEWS,
        "levels": raw["levels"],
        "ptpObservableLevels": raw["ptpObservableLevels"],
        "buttons": buttons,
        "menus": MENUS,
        "presets": PRESETS,
        "connectChecks": CONNECT_CHECKS,
    }

    # 热区必须落在画布内，否则那个按钮点不到
    W, H = 336, 280
    for b in buttons:
        h = b.get("hotspot") or {}
        if not h:
            raise SystemExit(f"{b['id']} 还是没有 hotspot")
        if h["shape"] == "circle":
            cx, cy, r = h["cx"], h["cy"], h["r"]
            if not (r <= cx <= W - r and r <= cy <= H - r):
                raise SystemExit(f"{b['id']} 热区出界: {h}")
            if not h.get("shape"):
                raise SystemExit(f"{b['id']} 缺 shape")
        else:
            x, y, w, hh = h["x"], h["y"], h["w"], h["h"]
            if x < 0 or y < 0 or x + w > W or y + hh > H:
                raise SystemExit(f"{b['id']} 热区出界: {h}")

    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"补了 {added} 个按钮的坐标")
    print(f"按钮 {len(buttons)} 个，视角 {len(VIEWS)} 个，菜单 {len(MENUS)} 条，预设 {len(PRESETS)} 个")
    print(f"写出 {OUT}  {OUT.stat().st_size} 字节")
    from collections import Counter
    print("各视角按钮数:", dict(Counter(b["view"] for b in buttons)))


if __name__ == "__main__":
    main()
