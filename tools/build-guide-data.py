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
import sys

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

# ---------------------------------------------------------------- schema
#
# 与 CamCoach/Model/CameraData.swift 一一对应。
#
# 为什么要有这个：Swift 的 Codable 字段类型写错，编译期完全查不出来，
# 要等 App 真的跑起来解码才炸，报的还是一句「数据格式不对」。
# build 6 就是这么翻车的——`device` 在 JSON 里是对象，Swift 写成了 String。
# 改 Swift 结构时这里也要跟着改，否则校验会放行一份解不出来的 JSON。
#
# 约定的写法：
#   str / int          基本类型
#   [x]                数组，元素是 x
#   {k: x, ...}        对象，每个键都要在
#   ("opt", x)         x 或 null
#   ("dict", k, v)     键值都是字符串的字典
#   ("number",)        int 或 float 都行
#   ("hotspot",)       按 shape 分支校验坐标
SCHEMA = {
    "schemaVersion": int,
    "device": {
        "model": str,
        "name": str,
        "firmwareBaseline": ("opt", str),
        "contentNote": ("opt", str),
        "disclaimer": ("opt", str),
    },
    "views": [{"id": str, "name": str, "hint": str}],
    "levels": ("dict", str, str),
    "ptpObservableLevels": ("dict", str, str),
    "buttons": [{
        "id": str,
        "name": str,
        "aliases": [str],
        "view": str,
        "hotspot": ("hotspot",),
        "level": str,
        "location": str,
        "default": str,
        "whatItDoes": str,
        "howToUse": str,
        "whyItMatters": str,
        "changeIt": str,
        "misconception": str,
        "ptpObservable": {
            "level": str,
            "property": ("opt", str),
            "note": str,
        },
    }],
    "menus": [{"want": str, "path": str, "note": str}],
    "presets": [{"name": str, "desc": str, "params": str, "warn": str, "steps": [str]}],
    "connectChecks": [{"title": str, "detail": str}],
}


def check_type(value, spec, path, errors):
    """按 SCHEMA 递归校验。errors 收全部问题，不是遇到第一个就停。"""
    if spec is str:
        if not isinstance(value, str):
            errors.append(f"{path}: 要字符串，实际 {type(value).__name__}")
    elif spec is int:
        if isinstance(value, bool) or not isinstance(value, int):
            errors.append(f"{path}: 要整数，实际 {type(value).__name__}")
    elif isinstance(spec, tuple):
        tag = spec[0]
        if tag == "opt":
            if value is not None:
                check_type(value, spec[1], path, errors)
        elif tag == "number":
            if isinstance(value, bool) or not isinstance(value, (int, float)):
                errors.append(f"{path}: 要数字，实际 {type(value).__name__}")
        elif tag == "dict":
            if not isinstance(value, dict):
                errors.append(f"{path}: 要对象，实际 {type(value).__name__}")
                return
            for k, v in value.items():
                check_type(v, spec[2], f"{path}.{k}", errors)
        elif tag == "hotspot":
            if not isinstance(value, dict):
                errors.append(f"{path}: 要对象，实际 {type(value).__name__}")
                return
            shape = value.get("shape")
            keys = ("cx", "cy", "r") if shape == "circle" else ("x", "y", "w", "h")
            if shape not in ("circle", "rect"):
                errors.append(f"{path}.shape: 只能是 circle 或 rect，实际 {shape!r}")
                return
            for k in keys:
                if k not in value:
                    errors.append(f"{path}.{k}: 缺字段")
                else:
                    check_type(value[k], ("number",), f"{path}.{k}", errors)
    elif isinstance(spec, list):
        if not isinstance(value, list):
            errors.append(f"{path}: 要数组，实际 {type(value).__name__}")
            return
        for i, item in enumerate(value):
            check_type(item, spec[0], f"{path}[{i}]", errors)
    elif isinstance(spec, dict):
        if not isinstance(value, dict):
            errors.append(f"{path}: 要对象，实际 {type(value).__name__}")
            return
        for k, sub in spec.items():
            if k not in value:
                errors.append(f"{path}.{k}: 缺字段")
            else:
                check_type(value[k], sub, f"{path}.{k}", errors)
    else:
        errors.append(f"{path}: SCHEMA 里写了个不认识的规则 {spec!r}")


def main():
    check_only = "--check" in sys.argv

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

    # 写盘之前先过一遍 Swift 结构。这一步是 build 6 那次翻车之后加的：
    # device 写成 String 而 JSON 是对象，编译全绿，装上直接白屏。
    errors = []
    check_type(out, SCHEMA, "$", errors)
    if errors:
        print("生成的 JSON 和 CameraData.swift 对不上：", file=sys.stderr)
        for e in errors[:20]:
            print("  " + e, file=sys.stderr)
        if len(errors) > 20:
            print(f"  ... 还有 {len(errors) - 20} 条", file=sys.stderr)
        raise SystemExit(1)

    expected = json.dumps(out, ensure_ascii=False, indent=2)

    # --check：不写盘，只确认磁盘上那份是脚本生成的、而且和 Swift 结构对得上。
    # CI 里跑这个，能挡住「手改了 JSON」和「改了 Swift 没同步数据」两种情况。
    if check_only:
        current = OUT.read_text(encoding="utf-8") if OUT.exists() else ""
        if current != expected:
            print("磁盘上的 camcoach-data.json 和脚本生成的不一致，"
                  "重跑一次 tools/build-guide-data.py，别手改产物", file=sys.stderr)
            return 1
        print(f"内容数据校验通过：{len(buttons)} 个按钮、{len(VIEWS)} 个视角、"
              f"{len(MENUS)} 条菜单、{len(PRESETS)} 个预设")
        return 0

    OUT.write_text(expected, encoding="utf-8")

    print(f"补了 {added} 个按钮的坐标")
    print(f"按钮 {len(buttons)} 个，视角 {len(VIEWS)} 个，菜单 {len(MENUS)} 条，预设 {len(PRESETS)} 个")
    print(f"写出 {OUT}  {OUT.stat().st_size} 字节")
    from collections import Counter
    print("各视角按钮数:", dict(Counter(b["view"] for b in buttons)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
