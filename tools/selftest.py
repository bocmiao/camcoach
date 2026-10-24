#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""apple-auto.py 的离线自测。

它不联网，也不碰 Apple。验的是「除跟 Apple 说话之外」的全部环节：

  1. JWT 的 ES256 签名能不能被公钥验通（签错 CI 会 401，白等 8 分钟）
  2. CSR 能不能被正确解析、公钥和私钥是否配对
  3. .p12 能不能用生成的密码读回来（读不回来 CI 导入就失败）
  4. 整个 6 步流程在 mock 响应下能不能走完并落齐文件

跑法：
  python selftest.py
"""

import base64
import importlib.util
import json
import os
import shutil
import sys
import tempfile

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

HERE = os.path.dirname(os.path.abspath(__file__))
PASS = 0
FAIL = 0


def check(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print("  [PASS] " + name)
    else:
        FAIL += 1
        print("  [FAIL] " + name + ("  <- " + detail if detail else ""))


def _is_der_cert(path):
    try:
        from cryptography import x509

        with open(path, "rb") as f:
            x509.load_der_x509_certificate(f.read())
        return True
    except Exception:
        return False


def load_module():
    path = os.path.join(HERE, "apple-auto.py")
    spec = importlib.util.spec_from_file_location("appleauto", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main():
    mod = load_module()

    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.hazmat.primitives.asymmetric.utils import encode_dss_signature

    tmp = tempfile.mkdtemp(prefix="camcoach-selftest-")
    try:
        # ---------------------------------------------------------- 1. JWT
        print()
        print("  1. JWT 的 ES256 签名")

        api_priv = ec.generate_private_key(ec.SECP256R1())
        p8_path = os.path.join(tmp, "AuthKey_TEST.p8")
        with open(p8_path, "wb") as f:
            f.write(
                api_priv.private_bytes(
                    encoding=serialization.Encoding.PEM,
                    format=serialization.PrivateFormat.PKCS8,
                    encryption_algorithm=serialization.NoEncryption(),
                )
            )

        token = mod.make_jwt(p8_path, "TESTKEY123", "69a6de7c-0000-0000-0000-000000000000")
        parts = token.split(".")
        check("JWT 是三段结构", len(parts) == 3, "实际 " + str(len(parts)) + " 段")

        def unpad(s):
            return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))

        header = json.loads(unpad(parts[0]))
        payload = json.loads(unpad(parts[1]))
        check("header.alg = ES256", header.get("alg") == "ES256")
        check("header.kid 正确", header.get("kid") == "TESTKEY123")
        check("aud = appstoreconnect-v1", payload.get("aud") == "appstoreconnect-v1")
        check(
            "exp - iat <= 1200 秒（Apple 上限）",
            payload.get("exp", 0) - payload.get("iat", 0) <= 1200,
            "实际 " + str(payload.get("exp", 0) - payload.get("iat", 0)),
        )

        sig = unpad(parts[2])
        check("签名是 64 字节 raw 格式", len(sig) == 64, "实际 " + str(len(sig)))
        r = int.from_bytes(sig[:32], "big")
        s = int.from_bytes(sig[32:], "big")
        try:
            api_priv.public_key().verify(
                encode_dss_signature(r, s),
                (parts[0] + "." + parts[1]).encode(),
                ec.ECDSA(hashes.SHA256()),
            )
            check("签名可被公钥验通", True)
        except Exception as e:
            check("签名可被公钥验通", False, str(e))

        # ---------------------------------------------------------- 2. CSR
        print()
        print("  2. 私钥与 CSR")
        key, key_pem, csr_pem = mod.gen_key_and_csr()
        check("私钥是 2048 位", key.key_size == 2048, "实际 " + str(key.key_size))

        csr = x509.load_pem_x509_csr(csr_pem)
        check("CSR 自签名校验通过", csr.is_signature_valid)
        cn = csr.subject.get_attributes_for_oid(x509.oid.NameOID.COMMON_NAME)[0].value
        check("CSR 的 CN 是 CamCoach Distribution", cn == "CamCoach Distribution", cn)

        csr_pub = csr.public_key().public_numbers()
        key_pub = key.public_key().public_numbers()
        check("CSR 公钥与私钥配对", csr_pub.n == key_pub.n and csr_pub.e == key_pub.e)

        csr_b64 = base64.b64encode(csr_pem).decode("ascii")
        check("CSR 可 base64 编码后还原", base64.b64decode(csr_b64) == csr_pem)

        # ---------------------------------------------------------- 3. p12
        print()
        print("  3. .p12 打包（CI 导入用）")
        from cryptography.hazmat.primitives.serialization import Encoding

        # 自签一张证书冒充 Apple 签发的，只为验证 p12 打包/解包链路
        import datetime

        from cryptography.hazmat.primitives import hashes as H
        from cryptography.x509.oid import NameOID

        now = datetime.datetime.now(datetime.timezone.utc)
        fake_cert = (
            x509.CertificateBuilder()
            .subject_name(csr.subject)
            .issuer_name(csr.subject)
            .public_key(key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(now - datetime.timedelta(days=1))
            .not_valid_after(now + datetime.timedelta(days=365))
            .sign(key, H.SHA256())
        )
        fake_der = fake_cert.public_bytes(Encoding.DER)
        check("假证书是 DER 编码", len(fake_der) > 500, "长度 " + str(len(fake_der)))

        pw = mod.rand_password()
        check("随机密码长度 24 且只含字母数字", len(pw) == 24 and pw.isalnum(), pw)

        p12_bytes = mod.build_p12(key, fake_der, pw)
        p12_path = os.path.join(tmp, "test.p12")
        with open(p12_path, "wb") as f:
            f.write(p12_bytes)
        check(".p12 文件已写出", os.path.getsize(p12_path) > 1000)

        from cryptography.hazmat.primitives.serialization import pkcs12

        with open(p12_path, "rb") as f:
            got_key, got_cert, _ = pkcs12.load_key_and_certificates(f.read(), pw.encode())
        check("用生成的密码能读回 .p12", got_key is not None and got_cert is not None)
        check(".p12 里的证书就是原证书", got_cert.public_bytes(Encoding.DER) == fake_der)

        bad_pw_ok = True
        try:
            pkcs12.load_key_and_certificates(p12_bytes, b"wrong-password")
            bad_pw_ok = False
        except Exception:
            bad_pw_ok = True
        check("错误密码读不出来（密码确实生效）", bad_pw_ok)

        # ---------------------------------------------------------- 4. 全流程
        print()
        print("  4. 六步流程编排（mock 掉 Apple 的响应）")

        out_dir = os.path.join(tmp, "cert")
        calls = []

        def mint_matching_cert(csr_b64):
            """按流程刚写盘的私钥 + CSR 现签一张假证书，冒充 Apple 的签发结果。

            必须动态生成：流程内部会自己生成新私钥，只有用它签出来的证书
            才能和 .p12 打包时的私钥配对。写死一张会让测试假失败。
            """
            kpath = os.path.join(out_dir, "distribution.key")
            with open(kpath, "rb") as f:
                k = serialization.load_pem_private_key(f.read(), password=None)
            inner = x509.load_pem_x509_csr(base64.b64decode(csr_b64))
            import datetime

            now2 = datetime.datetime.now(datetime.timezone.utc)
            c = (
                x509.CertificateBuilder()
                .subject_name(inner.subject)
                .issuer_name(inner.subject)
                .public_key(k.public_key())
                .serial_number(x509.random_serial_number())
                .not_valid_before(now2 - datetime.timedelta(days=1))
                .not_valid_after(now2 + datetime.timedelta(days=365))
                .sign(k, hashes.SHA256())
            )
            return c.public_bytes(serialization.Encoding.DER)

        def fake_api(method, path, token, body=None):
            calls.append((method, path))
            if path.startswith("/v1/bundleIds?limit=1"):
                return 200, {
                    "data": [{"id": "BID1", "attributes": {"identifier": "x.y", "seedId": "ABCDE12345"}}]
                }
            if path.startswith("/v1/bundleIds?filter"):
                return 200, {"data": []}
            if method == "POST" and path == "/v1/bundleIds":
                return 201, {
                    "data": {"id": "BID2", "attributes": {"identifier": "com.camcoach.app", "seedId": "ABCDE12345"}}
                }
            if method == "POST" and path == "/v1/certificates":
                der = mint_matching_cert(body["data"]["attributes"]["csrContent"])
                return 201, {
                    "data": {
                        "id": "CERT1",
                        "attributes": {
                            "name": "CamCoach Distribution",
                            "certificateContent": base64.b64encode(der).decode(),
                        },
                    }
                }
            if path.startswith("/v1/certificates?filter"):
                # 复用分支靠内容比对认证书，所以必须返回和本地 .cer 一模一样的字节
                cer_local = os.path.join(out_dir, "distribution.cer")
                if os.path.exists(cer_local):
                    with open(cer_local, "rb") as f:
                        der = f.read()
                    return 200, {
                        "data": [
                            {
                                "id": "CERT1",
                                "attributes": {
                                    "name": "CamCoach Distribution",
                                    "certificateContent": base64.b64encode(der).decode(),
                                },
                            }
                        ]
                    }
                return 200, {"data": []}
            if path.startswith("/v1/profiles?filter"):
                return 200, {"data": []}
            if method == "POST" and path == "/v1/profiles":
                return 201, {
                    "data": {"id": "PROF1", "attributes": {"name": "CamCoach AppStore", "profileContent": base64.b64encode(b"FAKE-PROFILE").decode()}}
                }
            return 200, {"data": []}

        mod.api = fake_api
        sys.argv = [
            "apple-auto.py",
            "--p8", p8_path,
            "--key-id", "TESTKEY123",
            "--issuer-id", "69a6de7c-0000-0000-0000-000000000000",
            "--out", out_dir,
        ]

        import contextlib

        buf = []
        with contextlib.redirect_stdout(type("T", (), {"write": lambda self, s: buf.append(s), "flush": lambda self: None})()):
            try:
                mod.main()
                ran = True
                err = ""
            except SystemExit as e:
                ran = (e.code in (0, None))
                err = "SystemExit " + str(e.code)
        check("流程无异常跑完", ran, err)
        log = "".join(buf)

        for fn in ["distribution.key", "distribution.certSigningRequest", "distribution.cer",
                   "distribution.p12", "CamCoach.mobileprovision", "secrets.txt", "cert-id.txt"]:
            check("产物存在: " + fn, os.path.exists(os.path.join(out_dir, fn)))

        with open(os.path.join(out_dir, "secrets.txt"), encoding="utf-8") as f:
            sec = f.read()
        # 名字必须和 .github/workflows/ios.yml 里的 secrets.XXX 逐字一致
        for k in ["APPLE_TEAM_ID=ABCDE12345", "ASC_KEY_ID=TESTKEY123",
                  "IOS_PROFILE_NAME=CamCoach AppStore", "IOS_CERT_PASSWORD=",
                  "ASC_KEY_CONTENT=", "IOS_CERT_P12_BASE64=", "IOS_PROFILE_BASE64="]:
            check("secrets 含 " + k.split("=")[0], k in sec)

        # 长值必须是真 base64，不能是路径
        for name, expect_b64 in [("ASC_KEY_CONTENT", True), ("IOS_CERT_P12_BASE64", True),
                                 ("IOS_PROFILE_BASE64", True)]:
            got = ""
            for line in sec.splitlines():
                if line.startswith(name + "="):
                    got = line.split("=", 1)[1]
            is_b64 = False
            if got:
                try:
                    base64.b64decode(got, validate=True)
                    is_b64 = True
                except Exception:
                    is_b64 = False
            check(name + " 是合法的 base64 文本", got != "" and is_b64 and "\\" not in got)

        check("cert-id.txt 记下了证书 ID", os.path.exists(os.path.join(out_dir, "cert-id.txt")))

        first_calls = list(calls)
        check("首次运行调用了 POST /v1/certificates",
              ("POST", "/v1/certificates") in first_calls, str(first_calls[:6]))
        check(".cer 是真正的 DER 证书",
              _is_der_cert(os.path.join(out_dir, "distribution.cer")))

        # 幂等：再跑一次应该走复用分支
        calls.clear()
        buf = []
        with contextlib.redirect_stdout(type("T", (), {"write": lambda self, s: buf.append(s), "flush": lambda self: None})()):
            try:
                mod.main()
            except SystemExit:
                pass
        log2 = "".join(buf)
        check("二次运行走复用分支（不重新签证书）", "跳过重新签发" in log2, log2[-300:])
        check("二次运行仍然生成了描述文件",
              os.path.exists(os.path.join(out_dir, "CamCoach.mobileprovision")))


    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print()
    print("  " + "-" * 46)
    print("  通过 " + str(PASS) + " 项，失败 " + str(FAIL) + " 项")
    print("  " + "-" * 46)
    print()
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
