# CamCoach · 取景助手

[![工程校验](https://github.com/bocmiao/camcoach/actions/workflows/validate.yml/badge.svg)](https://github.com/bocmiao/camcoach/actions/workflows/validate.yml)

给新手用的相机使用助手。iPhone 用 USB 连上相机，认键、找设置、照着预设拨参数；连上之后能在手机上看到相机的实时画面和真实参数。

**当前状态：build 18 —— 已上传 TestFlight。实时取景 + 斑马纹 + 直方图 + 快门 + 改 ISO/曝光补偿 + 风格包与 .cube 调色包。**

**每一版改了什么：[CHANGELOG.md](CHANGELOG.md)。** 装新包之前先看这个，里面写清了这次该验证哪几处。

两条线现在都通了。

**认机器**：五个视角的机身图，点一下看这个键是干什么的、默认值是什么、什么时候该改、新手最容易搞错什么。

**当场纠错**：相机切到「遥控拍摄」（屏幕显示 `-PC-`），插上 USB，取景页右上角扳手做一次自检，连上之后按「开始取景」就能看到画面和相机里的真实参数。探针页还留着，它回答的是「这条链路断在哪一级」——自检做成 5 级阶梯，从上往下第一个红的就是断点，报告一键复制。

探针的设计原则是**只观察、不假设**：所有 Sony 私有码都没有官方文档，写死一条「正确流程」的话，第一个错误就会把后面全挡住。所以每个码单独发、单独记，`OperationNotSupported` 本身也是有用信息——它至少证明通道通了、只是码不对。

2026-10-24 实测走完的完整链路：验证 API 密钥 → 复用已有发布证书 → 导入 keychain → 安装描述文件 → XcodeGen 生成工程 → Archive → 导出 IPA → 上传 TestFlight，build 状态 `VALID`。全程在 Windows 上敲命令，没有 Mac。

---

## 为什么有这个东西

新手卡住的地方有两处，顺序是固定的。

**第一处是根本不认识手上的机器。** 模式盘该停哪档、C1 和 C3 谁管对焦区域、快门声音在哪个菜单里关——这些说明书都写了，但写在几百页 PDF 里，按 Sony 的功能分类排，跟脑子里的问法对不上。

**第二处是拍的时候不知道自己错了。** 主体在跑、快门还停在 1/60、这一张注定糊。相机自己不会说，说明书也不会当场说。

App 按这个顺序做：

1. **认机器**：按键图鉴、菜单反查、预设、上手清单。全部离线，看一遍能上手。
2. **当场纠错**：从取景流里算直方图、锐度、主体位移，预测这张会不会糊。越线了就说，没越线就闭嘴。这一步要等探针先证明能拿到画面。

不做问答机器人。问题库随便一搜都有，答得再全也不如指着机身上那个键告诉你它在哪。

实时反馈全部在本地算，不上传任何画面，不需要联网，也不调大模型。

---

## 现在能做什么

| 能力 | 状态 |
|---|---|
| 无 Mac 的 CI 构建链路 | ✅ 免签名编译已验证通过 |
| 按键图鉴（5 个视角 / 23 个键 / 14 个字段） | ✅ build 6 |
| 菜单反查（12 条，可搜可复制路径） | ✅ build 6 |
| 预设（5 组，含分步操作） | ✅ build 6 |
| 第一周上手清单（16 个键，勾选存本地） | ✅ build 6 |
| 相机能力自检（系统版本 / PTP 通道 / ImageCaptureCore 链接） | ✅ build 2 |
| 签名 + 上传 TestFlight | ✅ build 15 |
| USB 枚举相机、Sony 私有握手 | ✅ build 12，连测 5 轮全通 |
| 读拍摄参数 | ✅ build 13，快门/光圈/ISO/对焦/电量/可拍张数 |
| 曝光补偿、曝光模式 | ⚠️ 机身没通过 PTP 报出来，界面上如实标注 |
| 实时取景 | ✅ build 13，1024×680、约 10 fps |
| 高光斑马纹 | ✅ build 15 |
| 直方图 | ✅ build 15 |
| 远程快门 | ✅ build 14，拍完回传缩略图，可存相册 |
| 安全快门（按焦距） | ✅ build 15，焦距需手动选一次 |
| 改参数：ISO、曝光补偿 | 🔬 build 16 已实现，写入 + 回读确认，待真机验证 |
| 风格包（10 个内置，参数组合 + 强度 + 长按看原图） | ✅ build 18，App 内后期，不改相机直出 |
| 导入 .cube 3D LUT（长按删除） | ✅ build 18，只支持 3D，1D 会明确提示不支持 |
| 相机内创意风格（Creative Look） | ⬜ 要写机身，等写入通路验证 |
| 改参数：快门、光圈、模式 | ⬜ 等上面两条验证通过再动 |
| 阈值标定采样 | ✅ build 15，工具已就位，样本还没攒 |

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

### 一条命令发版

`tools/ship.py` 把整条链路收进一个入口：

```bash
python tools/ship.py doctor      # 体检，只读，先跑这个
python tools/ship.py setup       # 首次：证书 + p12 + Bundle ID + 描述文件
python tools/ship.py secrets     # 把 secrets 写进 GitHub
python tools/ship.py release     # 发版：build号+1 → 推送 → 构建 → 挂测试组
python tools/ship.py logs        # 构建失败时把日志压到能读的长度
python tools/ship.py status      # 分发状态速查
```

Windows 上双击 `tools\ship.cmd`，它会自己找 Python。

**`doctor` 为什么重要**：iOS 这条链的失败总发生在**最后一步**——编译、签名、导出全绿，上传时才说版本号不对；或者上传明明成功了，TestFlight 里却是空的（没分配测试组）。`doctor` 把"最后一秒才炸的失败"提前到"第一秒"，并且直接给出修法。

它还会查出一些你不一定知道的事，比如：

- 账号下的 Distribution 证书已经用掉几张（团队上限 2 张，满了就只能复用，不能再申请）
- 下一个 build 号会不会撞（撞了上传必被拒）
- App 名字里有没有第三方商标（内部测试没事，外部测试和上架必被拒）

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

## 凭据处理规矩

2026-10-24 出过一次问题，记在这里防止再犯。

排查 p12 格式问题时，`ios.yml` 里加过三行诊断：

```bash
echo "密码长度: ${#CERT_PASSWORD}"
echo "密码首字符: ${CERT_PASSWORD:0:1}"
echo "密码末字符: ${CERT_PASSWORD: -1}"
```

当时只想着把问题定位出来，忽略了一件事：**GitHub 的 secret 遮蔽只替换「完整的 secret 值」**。`${#VAR}`、`${VAR:0:1}` 这类切片不等于完整值，**完全不会被遮蔽**，原样写进日志。而这个仓库是公开的，Actions 日志任何 GitHub 用户都能读。

已在 `1bfbc5d` 移除。影响范围：15 次运行（2026-10-24 01:50–02:25，`#14`–`#28`）。因为密码是 24 位、大小写+数字的加密随机串，泄露长度和首尾各一个字符后仍有约 131 bit 熵，**密码本身不需要更换**。

**三条规矩：**

1. 任何 secret 都不进 `echo`——包括长度、首尾字符、哈希前缀这类「看起来无害」的派生值。派生值只要和秘密有确定性关系，就是泄露。
2. 诊断只用**布尔结果**：「能打开 / 打不开」已经足够定位 p12 类问题。
3. 需要区分故障原因时，用**非敏感量**——文件字节数、返回码、错误类型，不要碰密钥材料。

---

## 目录

```
project.yml                 工程描述（XcodeGen）
CamCoach/
  CamCoachApp.swift         入口
  RootView.swift            五个 tab，数据加载失败页
  Model/
    CameraData.swift        内容数据的 Codable 结构
    GuideProgress.swift     上手清单的勾选进度（UserDefaults）
  Guide/
    BodyDiagram.swift       五个视角的机身图 + 23 个热区
    BodyDiagramView.swift   图鉴页，机身图与列表双向联动
    ButtonDetailView.swift  单个按键的 14 个字段
    MenuSearchView.swift    菜单反查
    PresetListView.swift    预设与分步操作
    ChecklistView.swift     第一周认键清单
  Probe/
    ProbeView.swift         连相机 + 连接前 6 项检查
    CameraProbe.swift       PTP 会话与探测流程
    PTP.swift               PTP 容器编解码
  Resources/
    camcoach-data.json      打包进 App 的内容数据（生成产物，不改它）
  Info.plist                由 project.yml 生成，不入库
data/guide-source.json      按键文案源
tools/build-guide-data.py   生成上面那个 JSON
.github/workflows/
  ios.yml                   签名 + 构建 + 上传 TestFlight
  validate.yml              免签名校验（不需要证书，改代码就自动跑）
fastlane/Fastfile           仅负责上传 TestFlight
tools/apple-auto.py         一站式：证书 + Bundle ID + 描述文件全部走 API 自动生成
tools/apple-auto.cmd        Windows 双击入口
tools/ship.py               统一入口：doctor / setup / secrets / release / logs / status
tools/ship.cmd              Windows 双击入口（纯 ASCII，自己找 Python）
tools/testflight.py         上传后收尾：内部测试组 + 挂 build + 加测试员
tools/selftest.py           上面那个脚本的离线自测（91 项）
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
