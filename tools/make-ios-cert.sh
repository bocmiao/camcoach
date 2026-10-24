#!/usr/bin/env bash
# 在没有 Mac 的 Windows 上，生成 iOS 发布证书并打包成 CI 能用的格式。
#
# 用法（在 Git Bash 里跑）：
#   bash tools/make-ios-cert.sh step1     # 生成私钥和 CSR
#   ... 去 Apple 开发者网站上传 CSR、下载 .cer、创建描述文件 ...
#   bash tools/make-ios-cert.sh step2     # 合成 p12，输出所有要填进 GitHub Secrets 的值
#
# 为什么不用 fastlane match 自动生成：
# 如果让 CI 生成证书，私钥就生在了一台几分钟后会被销毁的机器上。
# Apple 那边会留下一张永远用不了的证书，而每个账号的发布证书名额有限。
# 所以：私钥必须生在你自己的机器上，CI 只负责导入。

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CERT_DIR="$ROOT/cert"
mkdir -p "$CERT_DIR"

step1() {
  echo "== 第一步：生成私钥和证书请求 =="
  echo

  if [ -f "$CERT_DIR/private.key" ]; then
    echo "cert/private.key 已存在。"
    read -r -p "要覆盖吗？这会让你之前生成的证书作废 [y/N] " ans
    case "$ans" in
      [yY]*) ;;
      *) echo "已取消。"; exit 0 ;;
    esac
  fi

  # 关键：先 cd 进 cert 目录，后面所有 openssl 参数只用裸文件名，不带任何斜杠。
  # 原因是 Git Bash 会「帮」你把看起来像路径的参数在 POSIX 和 Windows 格式之间转换，
  # 而这个转换在不同启动方式下（直接在 Git Bash 里跑 / 从 cmd 调起来）行为不一致，
  # 会导致 genrsa 能写、req 却读不到同一个文件。裸文件名没有斜杠，转换无从下手。
  mkdir -p "$CERT_DIR"
  cd "$CERT_DIR"

  openssl genrsa -out private.key 2048
  echo "  私钥 → cert/private.key"

  # -subj 里的 /CN=... 必须挡住路径转换，否则会被改写成 C:/Program Files/Git/CN=...
  MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' openssl req -new \
    -key private.key \
    -out request.crt \
    -subj "/CN=CamCoach Distribution/O=CamCoach/C=CN"
  echo "  请求 → cert/request.crt"
  echo
  echo "接下来手动做三件事（都在浏览器里，不需要 Mac）："
  echo
  echo "  1) 打开 https://developer.apple.com/account/resources/certificates/add"
  echo "     选 「Apple Distribution」，上传 cert/request.crt，下载得到的 .cer"
  echo "     把下载的文件改名成 distribution.cer 放进 cert/ 目录"
  echo
  echo "  2) 打开 https://developer.apple.com/account/resources/identifiers/add/bundleId"
  echo "     新建 App ID，Bundle ID 填：com.camcoach.app"
  echo
  echo "  3) 打开 https://developer.apple.com/account/resources/profiles/add"
  echo "     选 「App Store」，App ID 选上一步建的，证书选刚签发的，下载 .mobileprovision"
  echo "     改名成 distribution.mobileprovision 放进 cert/ 目录"
  echo
  echo "做完再跑： make-cert.cmd step2"
  echo "（如果你在 Git Bash 窗口里，等价命令是 bash tools/make-ios-cert.sh step2）"
}

step2() {
  echo "== 第二步：合成 p12 并输出 Secrets =="
  echo

  [ -f "$CERT_DIR/private.key" ]              || { echo "缺 cert/private.key，先跑 step1"; exit 1; }
  [ -f "$CERT_DIR/distribution.cer" ]         || { echo "缺 cert/distribution.cer（从 Apple 下载的证书）"; exit 1; }
  [ -f "$CERT_DIR/distribution.mobileprovision" ] || { echo "缺 cert/distribution.mobileprovision（从 Apple 下载的描述文件）"; exit 1; }

  cd "$CERT_DIR"

  # Apple 下载的是 DER 格式，openssl 要 PEM 才肯认
  openssl x509 -inform DER -in distribution.cer -out distribution.pem
  echo "  证书 → cert/distribution.pem"

  echo
  echo "提示：如果下面这次输入没反应（cmd 里通过 bash 调用时偶尔会这样），"
  echo "     可以先在 cmd 里执行  set P12_PASS=你的密码  然后再跑一次 step2。"
  if [ -n "${P12_PASS:-}" ]; then
    echo "  已从环境变量 P12_PASS 读到密码。"
  else
    read -r -s -p "给这个 p12 设一个密码（等下要填进 GitHub Secrets，记牢）： " P12_PASS || P12_PASS=""
    echo
  fi
  [ -n "${P12_PASS:-}" ] || { echo "密码不能为空"; exit 1; }

  openssl pkcs12 -export \
    -inkey private.key \
    -in distribution.pem \
    -name "CamCoach Distribution" \
    -out distribution.p12 \
    -passout "pass:$P12_PASS"
  echo "  打包 → cert/distribution.p12"

  # 全部转成 base64，GitHub Secrets 只吃纯文本
  openssl base64 -A -in distribution.p12             -out p12.b64
  openssl base64 -A -in distribution.mobileprovision -out profile.b64

  # 描述文件的"名字"要单独填，不在文件内容里，得从 plist 里挖
  PROFILE_NAME="$(security cms -D -i "$CERT_DIR/distribution.mobileprovision" 2>/dev/null \
    | grep -A1 '<key>Name</key>' | grep '<string>' | sed -E 's/.*<string>(.*)<\/string>.*/\1/' || true)"

  echo
  echo "======================================================"
  echo " 去 GitHub 仓库 → Settings → Secrets and variables → Actions"
  echo " 新建下面这 6 个 secret："
  echo "======================================================"
  echo
  echo "IOS_CERT_P12_BASE64   =  cert/p12.b64 的全部内容"
  echo "IOS_CERT_PASSWORD     =  你刚才设的密码"
  echo "IOS_PROFILE_BASE64    =  cert/profile.b64 的全部内容"
  echo "IOS_PROFILE_NAME      =  描述文件的名字（见下）"
  echo "APPLE_TEAM_ID         =  你的 Team ID（10 位，开发者网站右上角）"
  echo
  echo "描述文件名字（I found 的自动提取结果，可能为空）："
  echo "  ${PROFILE_NAME:-（没提取到，去开发者网站 Profile 列表看那一行的名字，例如 iOS Team Store Provisioning Profile: com.camcoach.app）}"
  echo
  echo "另外两个在 App Store Connect 里建："
  echo "  ASC_KEY_ID      =  Users and Access → Integrations → App Store Connect API → Key ID"
  echo "  ASC_ISSUER_ID   =  同一页面上方的 Issuer ID"
  echo "  ASC_KEY_CONTENT =  .p8 文件转 base64 的结果："
  echo "                     openssl base64 -A -in AuthKey_XXXX.p8 -out k.b64 && cat k.b64"
  echo
  echo "提示：p12.b64 / profile.b64 都很长，直接 cat 出来复制："
  echo "  cat cert/p12.b64 | clip        （clip 会复制到剪贴板）"
  echo "  cat cert/profile.b64 | clip"
  echo
  echo "填完这些，push 到 main 就会自动构建并上传 TestFlight。"
}

case "${1:-}" in
  step1) step1 ;;
  step2) step2 ;;
  *)
    echo "用法："
    echo "  bash tools/make-ios-cert.sh step1   生成私钥和 CSR"
    echo "  bash tools/make-ios-cert.sh step2   合成 p12 并列出要填的 Secrets"
    ;;
esac
