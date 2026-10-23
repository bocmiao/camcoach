# CamCoach · 取景助手

给新手用的相机取景辅助工具。iPhone 用 USB 连上相机，实时看画面、读参数，画面对了不说话，不对了告诉你该改哪个数。

**当前状态：v0.1.0 —— 只验证构建链路，还没有接入相机。**

这个版本唯一要证明的事：**没有 Mac，也能把 App 装到 iPhone 上**。界面上是一个自检清单，全绿就说明流水线通了。

---

## 为什么有这个东西

市面上的相机教程、按键说明、参数预设，随便一搜到处都是。写一本更好的说明书，没有意义。

真正缺的是**画面上正在发生的错**：主体在跑、快门还停在 1/60、这一张注定糊——相机自己不会说，说明书也不会当场说。

所以这个 App 不做内容库，做到两件事：

1. **预设**：你说"我想拍成背景虚化的人像"，它把整套参数（档位、光圈、快门下限、对焦模式、对焦区域、白平衡）写进相机。你不用知道光圈该是多少。
2. **体检**：从取景流里算直方图、锐度、主体位移，预测这张会不会糊。越线了就说，没越线就闭嘴。

全部在本地算，不上传任何画面，不需要联网，也不调大模型。

---

## 现在能做什么

| 能力 | 状态 |
|---|---|
| 无 Mac 的 CI 构建链路 | ✅ v0.1.0 |
| 相机能力自检（系统版本 / PTP 通道 / ImageCaptureCore 链接） | ✅ v0.1.0 |
| USB 枚举相机、Sony 私有握手 | ⬜ v0.2.0 |
| 读拍摄参数、写参数（含回读确认） | ⬜ v0.2.0 |
| 取景流 + 像素级体检 | ⬜ v0.3.0 |
| 意图预设 + 越线一键修正 | ⬜ v0.4.0 |

---

## 构建（不需要 Mac）

工程用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 描述，`.xcodeproj` 是生成产物、不入库。好处是工程配置可读、可 diff，在 Windows 上也能直接改。

构建跑在 GitHub Actions 的 `macos-latest` 上，产物经 TestFlight 分发到手机。

**为什么不本地编译**：这台机器没有 Mac。所以整个链路是 `push → CI 编译签名 → TestFlight → 手机安装`，一轮约 20–30 分钟。

### 一次性准备

```bash
# 第一步：生成私钥和 CSR
bash tools/make-ios-cert.sh step1

# 拿 cert/request.crt 去 Apple 开发者网站签证书，
# 建 App ID（Bundle ID: com.camcoach.app），建 App Store 类型描述文件，
# 下载的两个文件放进 cert/

# 第二步：合成 p12 并列出要填的 Secrets
bash tools/make-ios-cert.sh step2
```

然后在仓库 Settings → Secrets and variables → Actions 里填 8 个值，详见脚本输出。

### 触发构建

推 `main` 分支，或手动 Run workflow。

---

## 目录

```
project.yml                 工程描述（XcodeGen）
CamCoach/
  CamCoachApp.swift         入口
  ContentView.swift         自检页
  Info.plist                由 project.yml 生成，不入库
.github/workflows/ios.yml   构建流水线
fastlane/Fastfile           仅负责上传 TestFlight
tools/make-ios-cert.sh      在 Windows 上生成 iOS 发布证书
```

---

## 几个踩过的坑

写在这里，省得下次再踩：

- **绝不让 CI 生成证书。** runner 用完就销毁，私钥跟着没了，Apple 那边多一张永远用不了的证书，而发布证书名额有限。
- **上 TestFlight 必须用 App Store 类型的描述文件。** Development 类型需要绑定设备 UDID，会报一句很难懂的 `Your team has no devices from which to generate a provisioning profile`。
- **`security set-key-partition-list` 不能省。** 少了它，`codesign` 会弹 GUI 授权框，CI 里没人能点，任务挂到超时。
- **运动模糊别用互相关测速度。** 画面里一个小主体 + 大片静止背景时，互相关永远返回 0，因为最匹配的位置确实是"没动"。改用帧差质心：主体离开处变亮、到达处变暗，两块的质心之差就是位移。
- **纯数学的结论要再过一层常识。** 按 `模糊 = 速度 × 快门` 反解，主体几乎不动时会推出"1/8 秒就够"——数学没错，手持必抖。所以要加 1/125 的手持下限。

---

## 免责声明

这是一个**独立的第三方工具**，与索尼（Sony）无任何关联，未获其授权、认可或支持。文中出现的相机型号仅用于说明兼容性。

项目不包含、不调用任何索尼的私有 SDK、二进制或闭源组件。与相机通信走的是 ISO 15740（PTP）标准协议和该型号自身提供的公开连接模式（USB 遥控拍摄）。使用本软件的风险由使用者自行承担。

App 的名称、图标、界面文案中不出现任何厂商商标——这不只是洁癖，是上架审核的硬要求。

---

## License

[Apache License 2.0](LICENSE)

选它而不是 GPL/AGPL 的原因写在 [LICENSE 说明](docs/why-apache.md) 里。简述：**GPL 与 App Store 的分发条款不兼容**，选了就等于放弃上架；而 AGPL 对本地运行的 App 没有额外保护（它的网络条款在 App 上根本不触发）。
