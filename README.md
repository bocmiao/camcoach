# CamCoach · 取景助手

[![工程校验](https://github.com/bocmiao/camcoach/actions/workflows/validate.yml/badge.svg)](https://github.com/bocmiao/camcoach/actions/workflows/validate.yml)

给新手用的相机取景辅助工具。iPhone 用 USB 连上相机，实时看画面、读参数，画面对了不说话，不对了告诉你该改哪个数。

**当前状态：v1.0 (build 4) —— 已上传 TestFlight，状态 `VALID`，带相机探针。**

build 4 要回答一个问题：**iPhone 到底能不能通过 USB 跟 A7M4 说上话**。装上后把相机切到「遥控拍摄」（屏幕显示 `-PC-`），点「开始探测」，它会依次试标准 PTP 和 Sony 的那几个逆向私有命令码，每一步的返回码都原样记下来，最后「复制」出一份报告。

探针的设计原则是**只观察、不假设**：所有 Sony 私有码都没有官方文档，写死一条「正确流程」的话，第一个错误就会把后面全挡住。所以每个码单独发、单独记，`OperationNotSupported` 本身也是有用信息——它至少证明通道通了、只是码不对。

2026-10-24 实测走完的完整链路：验证 API 密钥 → 复用已有发布证书 → 导入 keychain → 安装描述文件 → XcodeGen 生成工程 → Archive → 导出 IPA → 上传 TestFlight，build 状态 `VALID`。全程在 Windows 上敲命令，没有 Mac。

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
| 无 Mac 的 CI 构建链路 | ✅ 免签名编译已验证通过 |
| 相机能力自检（系统版本 / PTP 通道 / ImageCaptureCore 链接） | ✅ build 2 |
| 签名 + 上传 TestFlight | ✅ build 4 状态 VALID |
| USB 枚举相机、Sony 私有握手 | 🔬 build 4 探针，待真机结果 |
| 读拍摄参数、写参数（含回读确认） | ⬜ 等探针结论 |
| 取景流 + 像素级体检 | ⬜ v0.3.0 |
| 意图预设 + 越线一键修正 | ⬜ v0.4.0 |

## 两条流水线

| 流水线 | 需要 Secrets | 什么时候跑 |
|---|---|---|
| **工程校验（免签名）** | ❌ 不需要 | 每次 push 自动跑。用 `CODE_SIGNING_ALLOWED=NO` 跳过签名，只验工程生成 + 编译 + fastlane |
| **iOS 构建并上传 TestFlight** | ✅ 需要 | **只能手动触发**（`workflow_dispatch`）。签名、导出 ipa、上传 |

分开的原因：签名问题（证书、profile、scope）和代码问题需要分开排查。混在一条流水线里，一个编译错误会被前面的签名失败挡住，看不到。

**上传这条为什么必须手动触发**：早期它挂在 `push` 上，结果改文档、改注释、甚至提交一版编不过的 Swift，都会自动跑完签名 + 上传，白烧一个 build 号。连着三次提交就吃掉 1/2/3，其中 build 1 根本编译不过也照样占了号。等真要发可用的包时被 Apple 拒：

```
ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE
The bundle version must be higher than the previously uploaded version: '3'
```

**上传不可撤销，占掉的号拿不回来。** 所以现在改成：改 `project.yml` 里的 `CURRENT_PROJECT_VERSION` → 手动点运行。日常改代码只走校验流水线，不花 build 号。

---

## 构建（不需要 Mac）

工程用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 描述，`.xcodeproj` 是生成产物、不入库。好处是工程配置可读、可 diff，在 Windows 上也能直接改。

构建跑在 GitHub Actions 的 `macos-latest` 上，产物经 TestFlight 分发到手机。

**为什么不本地编译**：这台机器没有 Mac。所以整个链路是 `push → CI 编译签名 → TestFlight → 手机安装`，一轮约 20–30 分钟。

### 一次性准备

**最短路径**：你只需要手动建一个 API 密钥，剩下的全自动。

1. 打开 `https://appstoreconnect.apple.com` → `用户和访问` → `集成` → `App Store Connect API` → `团队密钥` → 生成 API 密钥。权限选 **App Manager**。下载 `AuthKey_XXXXXXXXXX.p8`（只能下一次）。

2. 把 `.p8` 放进 `tools/`，双击 `tools/apple-auto.cmd`。它会依次完成：生成私钥和 CSR → 让 Apple 签成发布证书 → 合成 `.p12` → 建 Bundle ID → 建 App Store 描述文件 → 输出全部 Secrets。中途只会问你一个 Issuer ID。

3. 打开 `tools/cert/secrets.txt`，8 条已转好格式，逐条填进仓库 `Settings → Secrets and variables → Actions`。

详细到每一屏的说明在 [docs/cert-guide.md](docs/cert-guide.md)。脚本自带的离线自测 `python tools/selftest.py` 覆盖 JWT 签名、CSR、p12 打包和六步流程编排。

<details>
<summary>手动路径（不用 API 密钥）</summary>

在 `ios` 目录下：

```bat
:: 第一步：生成私钥和 CSR
make-cert step1

:: 拿 cert\request.crt 去 Apple 开发者网站签证书，
:: 建 App ID（Bundle ID: com.camcoach.app），建 App Store 类型描述文件，
:: 下载的两个文件放进 cert\

:: 第二步：合成 p12 并列出要填的 Secrets
make-cert step2
```

> **别直接在 cmd 里敲 `bash`。** Git for Windows 只把 `Git\cmd` 加进 PATH，那里只有 `git.exe`，没有 `bash.exe`。`make-cert.cmd` 会自己去 `C:\Program Files\Git\bin\bash.exe` 找。
> 用 Git Bash 窗口的话，`bash tools/make-ios-cert.sh step1` 同样可以。
>
> 顺带提醒：`.cmd` 文件里不能写中文——cmd.exe 按 GBK 读批处理文件，UTF-8 的中文会被切碎当成命令执行。所以那个文件是纯英文的，中文提示都由 bash 或 Python 输出。

</details>

### 触发构建

**上传流水线只能手动触发**（`gh workflow run ios.yml --ref main`，或在 Actions 页面点 Run workflow）。

推 `main` 只会跑免签名的编译校验 —— 改文档、改注释、提交半成品都不会白烧 build 号。发版前记得先把 `project.yml` 里的 `CURRENT_PROJECT_VERSION` 加一。

### 上传之后还有一步（别漏）

**上传成功、build 状态 `VALID`，不代表手机上能看到它。**

build 4 就是这么栽的：Actions 全绿、ASC 里 `VALID`，人打开 TestFlight 结果什么都没有 —— 因为 `betaGroups` 是空的。上传只完成了一半，还差三步：

1. App 有一个**内部测试组**
2. 这个 build **分配进**那个组
3. 自己的 Apple ID **在组里**

```
python tools/testflight.py status     # 只读，看缺哪一环
python tools/testflight.py attach     # 补齐，幂等
```

**API 上最坑的一点**：`POST /v1/betaGroups` 默认建的是**外部组**。外部组的第一个 build 必须过 Beta App Review，等 1~3 天。内部组必须在 attributes 里显式写 `"isInternalGroup": true` —— 而 `PATCH` 改不了这个字段（`The attribute 'isInternalGroup' can not be included in a 'UPDATE' operation`），建错了只能删掉重建。

另外 `POST /v1/betaTesters` 必须同时带 `betaGroups` 或 `builds` 关系，只传 email 会报 `Either betaGroups or builds relationship is required when creating betaTesters`。

---

## 目录

```
project.yml                 工程描述（XcodeGen）
CamCoach/
  CamCoachApp.swift         入口
  ContentView.swift         自检页
  Info.plist                由 project.yml 生成，不入库
.github/workflows/
  ios.yml                   签名 + 构建 + 上传 TestFlight
  validate.yml              免签名校验（不需要证书，改代码就自动跑）
fastlane/Fastfile           仅负责上传 TestFlight
tools/apple-auto.py         一站式：证书 + Bundle ID + 描述文件全部走 API 自动生成
tools/apple-auto.cmd        Windows 双击入口
tools/testflight.py         上传后收尾：内部测试组 + 挂 build + 加测试员
tools/selftest.py           上面那个脚本的离线自测（41 项）
tools/make-ios-cert.sh      手动路径：纯 openssl 生成证书
make-cert.cmd               手动路径的 Windows 入口
docs/cert-guide.md          证书与 Secrets 的完整操作说明
docs/why-apache.md          License 决策推导
```

---

## 几个踩过的坑

写在这里，省得下次再踩：

- **绝不让 CI 生成证书。** runner 用完就销毁，私钥跟着没了，Apple 那边多一张永远用不了的证书，而发布证书名额有限。
- **上 TestFlight 必须用 App Store 类型的描述文件。** Development 类型需要绑定设备 UDID，会报一句很难懂的 `Your team has no devices from which to generate a provisioning profile`。
- **`security set-key-partition-list` 不能省。** 少了它，`codesign` 会弹 GUI 授权框，CI 里没人能点，任务挂到超时。
- **运动模糊别用互相关测速度。** 画面里一个小主体 + 大片静止背景时，互相关永远返回 0，因为最匹配的位置确实是"没动"。改用帧差质心：主体离开处变亮、到达处变暗，两块的质心之差就是位移。
- **纯数学的结论要再过一层常识。** 按 `模糊 = 速度 × 快门` 反解，主体几乎不动时会推出"1/8 秒就够"——数学没错，手持必抖。所以要加 1/125 的手持下限。

第一次上传 TestFlight 连踩四个坑，都发生在上传阶段，编译和签名全是绿的：

- **p12 必须用 3DES + SHA1 MAC。** Python 的 `cryptography` 默认给 AES-256 + SHA256 MAC，openssl 读得懂，但 macOS 的 `security import` 报 `MAC verification failed (wrong password?)`——提示说密码错，其实密码是对的，是算法不认。用 `openssl pkcs12 -export -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1` 重新封装才行。
- **必须有 App 图标。** 没有 asset catalog 会报 `90713 Missing CFBundleIconName` + `90022 Missing 120x120 icon`。光把 PNG 放进目录不够，`project.yml` 里还得有 `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`，否则图标不会被编进包。
- **App ID 和 App 记录是两回事。** Developer 后台建的是 Identifier，TestFlight 要的是 App Store Connect 里的「App」记录。后者 Apple 没有 API，只能网页手动建一次。少了它会报 `Couldn't find app 'xxx' on the account`。
- **版本号要和 App Store Connect 里的一致。** 包里写 0.1.0、ASC 里建的是 1.0，上传报 `409 ENTITY_ERROR.RELATIONSHIP.INVALID.INVALID_STATE`（buildUpload）。另外 build 号每次上传都得是没用过的。

还有一个反直觉的：**这个 409 有时意味着上传其实成功了**——Apple 收下二进制后有几秒钟不在 builds 列表里，altool 自动重试时撞上"build 已存在"就报 409。所以看到这个错先去 builds 列表查，别直接重传（会造成重复上传）。

Windows 上的三个坑（都是实际撞出来的）：

- **cmd 里没有 `bash`。** Git for Windows 只把 `Git\cmd` 加进 PATH，那里只有 `git.exe`；`bash.exe` 在 `Git\bin`，没进 PATH。所以 `git` 好用但 `bash` 报"不是内部或外部命令"。`make-cert.cmd` 不依赖 PATH，自己去常见位置找。
- **`.cmd` 文件里一个字中文都不能写。** cmd.exe 按当前 OEM 代码页（简体中文系统是 GBK）读批处理文件，UTF-8 的中文字节会被切碎，注释行变成"不是内部或外部命令"。`.cmd` 保持纯 ASCII，中文提示交给 bash 输出（配合 `chcp 65001`）。
- **Git Bash 的路径转换在不同启动方式下不一致。** 同一个脚本，直接在 Git Bash 里跑能过，从 cmd 调起来就可能在 `openssl genrsa` 写成功之后、`openssl req` 读不到同一个文件（它拿到的路径被转成了 `/c/Users/...`）。避开办法：先 `cd` 进目标目录，openssl 参数只用裸文件名、不带斜杠，转换就无从下手。

---

## 免责声明

这是一个**独立的第三方工具**，与索尼（Sony）无任何关联，未获其授权、认可或支持。文中出现的相机型号仅用于说明兼容性。

项目不包含、不调用任何索尼的私有 SDK、二进制或闭源组件。与相机通信走的是 ISO 15740（PTP）标准协议和该型号自身提供的公开连接模式（USB 遥控拍摄）。使用本软件的风险由使用者自行承担。

App 的名称、图标、界面文案中不出现任何厂商商标——这不只是洁癖，是上架审核的硬要求。

---

## License

[Apache License 2.0](LICENSE)

选它而不是 GPL/AGPL 的原因写在 [LICENSE 说明](docs/why-apache.md) 里。简述：**GPL 与 App Store 的分发条款不兼容**，选了就等于放弃上架；而 AGPL 对本地运行的 App 没有额外保护（它的网络条款在 App 上根本不触发）。
