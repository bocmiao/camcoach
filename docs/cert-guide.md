# 证书与描述文件

## 先分清三个网址

Apple 把东西拆在三个站上，这是最容易卡住的地方：

| 网址 | 是什么 | 证书在这儿吗 |
|---|---|---|
| `developer.apple.com` | 宣传页，满屏"加入开发者计划" | ❌ |
| `developer.apple.com/account` | 开发者后台，证书 / App ID / 描述文件 | ✅ 有，但**不用去** |
| `appstoreconnect.apple.com` | 上架后台，管 App / TestFlight / **API 密钥** | ❌ 但**从这里入手最短** |

`developer.apple.com/account` 登录后，顶部菜单里第一项 `Certificates, Identifiers & Profiles` 就是证书的家，左侧分 `Certificates` / `Identifiers` / `Devices` / `Profiles` / `Keys`。

你不必去点它——下面这条路把这五个页面全绕过了。

---

## 一、手动建一个 API 密钥

Apple 不允许用 API 创建 API 密钥（自举问题），所以这一步绕不过去，大约五分钟。

1. **打开 `https://appstoreconnect.apple.com`**，用付费开发者账号登录。

2. 顶部菜单点 **`用户和访问`**（`Users and Access`）。

3. 页面上方切到 **`集成`**（`Integrations`）标签。

4. 左侧选 **`App Store Connect API`**，右边区域标题附近有 **`团队密钥`**（`Team Keys`）。

   **如果这里只有「请求访问权限」（`Request Access`）而不是「生成 API 密钥」**：点它，勾选条款，提交，等 Apple 审核通过后才能建密钥。第一次用 API 的账号都是这个状态——Apple 官方文档明确要求 Account Holder 先申请。这一步只有账号持有人能做（你自己的付费账号就是）。

5. 点 **`生成 API 密钥`**（或右上角 `+`）。弹窗只有两项：
   - 名称：`camcoach-ci`
   - 访问权限：**App 经理**（`App Manager`）

   两个别弄错：
   - 不要选 `Developer`——读不了证书，后面 403。
   - **不要用「个人 API 密钥」（Individual Key）**。Apple 文档写明个人密钥 `aren't able to use Provisioning endpoints`，建不了证书和描述文件。必须用 **团队密钥**。

6. 生成后页面上会出现两个值：

   ```
   Issuer ID:  69a6de7c-1a2b-3c4d-5e6f-7890abcdef12   ← 整个团队共用一个
   Key ID:     ABC123DEFG                              ← 每把钥匙一个
   ```

   点每行右边的 **`下载 API 密钥`**，得到 `AuthKey_ABC123DEFG.p8`。

   ⚠️ **只能下载一次。** 关掉页面就再也拿不到，只能吊销重建。

---

## 二、剩下全自动

把 `.p8` 放进 `tools/`，双击 `tools/apple-auto.cmd`。

脚本做六件事：

| 步骤 | 干什么 |
|---|---|
| 1 | 验证 API 密钥能连上、有权限 |
| 2 | 本地生成 RSA 2048 私钥 + CSR（不需要 openssl，不需要 Mac） |
| 3 | 上传 CSR，让 Apple 签成发布证书，下载 `.cer` |
| 4 | 合成 `.p12`（CI 导入用，密码自动生成） |
| 5 | 建 Bundle ID `com.camcoach.app`，已存在就复用 |
| 6 | 建 App Store 描述文件，下载 `.mobileprovision` |

中间只问你一个 **Issuer ID**。Key ID 从文件名 `AuthKey_<KeyID>.p8` 自动读，`.p8` 路径也在当前目录 / tools / 下载 / 桌面自动找。

产物落在 `tools/cert/`：

```
distribution.key            私钥（别外传）
distribution.cer            Apple 签发的证书
distribution.p12            CI 导入用的打包证书
CamCoach.mobileprovision    描述文件
secrets.txt                 8 个 Secret 的成品，可直接粘贴
cert-id.txt                 证书 ID，重跑时用来复用
```

脚本是幂等的：再跑一次会复用已有证书，不会重复占用名额（Apple 只给 2 张发布证书）。想强制重签加 `--force`。

---

## 三、填 Secrets

仓库 `Settings → Secrets and variables → Actions → New repository secret`。

打开 `tools/cert/secrets.txt`，**8 条已经全部转好格式**（三个超长 base64 也包括），逐条复制粘贴，名字照抄等号左边。

| Secret | 内容 | 形态 |
|---|---|---|
| `APPLE_TEAM_ID` | 10 位字母数字 | 明文 |
| `ASC_KEY_ID` | 10 位 Key ID | 明文 |
| `ASC_ISSUER_ID` | 长串 UUID | 明文 |
| `IOS_CERT_PASSWORD` | 脚本生成的 24 位密码 | 明文 |
| `IOS_PROFILE_NAME` | `CamCoach AppStore` | 明文 |
| `ASC_KEY_CONTENT` | .p8 的 base64 | 长串 |
| `IOS_CERT_P12_BASE64` | .p12 的 base64 | 长串 |
| `IOS_PROFILE_BASE64` | .mobileprovision 的 base64 | 长串 |

名字必须逐字一致。差一个字，CI 读到空值，然后在签名那步报一句和真正原因无关的错——最难查的一类失败。

---

## 四、排错

| 现象 | 原因 | 怎么办 |
|---|---|---|
| `401 NOT_AUTHORIZED` | Key ID / Issuer ID 抄错，或 .p8 不是 API 密钥 | 核对；Issuer ID 是带横杠的 UUID |
| `403 Forbidden` | 密钥权限不够 | 吊销重建，Access 选 App Manager 或 Admin |
| 409 / 证书数量到上限 | Apple 只给 2 张发布证书 | `developer.apple.com/account` → Certificates → 吊销一张旧的 |
| `Certificate public key and provided private key do not match` | 私钥和证书不是一对 | 加 `--force` 重跑 |
| 双击 .cmd 闪一下就没 | Python 没装或不在 PATH | 装 Python 时勾 *Add python.exe to PATH* |
| 缺 `cryptography` | 库没装 | 脚本会自动装；失败就 `python -m pip install cryptography` |
| 中文乱码 | 终端代码页不是 UTF-8 | .cmd 已 `chcp 65001`；仍乱码就换 Windows Terminal |

---

## 五、手动路径

如果不想用 API 密钥，`tools/make-ios-cert.sh` 走纯 openssl：

```bat
make-cert step1   :: 生成私钥和 CSR
make-cert step2   :: 合成 p12 并列出 Secrets
```

中间要自己去 `developer.apple.com/account` 手动完成：上传 CSR 签证书 → 建 App ID → 建描述文件 → 下载两个文件到 `cert/`。

这条路 Windows 上有个坑：`openssl genrsa` 写完文件后，`openssl req` 可能读不到（路径被 MSYS 转成 `/c/Users/...`）。避开办法是先 `cd` 进目录，参数只用裸文件名。脚本里已经这么处理了。

---

## 六、为什么要保管好 `tools/cert/`

里面是**私钥材料**，和密码同级。`.gitignore` 已排除 `cert/`、`*.p8`、`*.p12`、`*.key`、`*.b64`、`secrets.txt`，别 `git add -f` 上去。

反过来，`ASC_KEY_ID` / `ASC_ISSUER_ID` / `APPLE_TEAM_ID` 不是秘密，泄露的风险是别人能用你的身份操作 App——所以也不要贴到公开 issue 里。
