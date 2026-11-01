#!/bin/bash
# 还原固定的 apk/usign 签名密钥到 <openwrt根>。
#   参数1: openwrt 源码根（= TOPDIR）
#   环境变量: PONWRT_SIGNING_KEYS = tar.gz 的 base64，内含
#             private-key.pem / public-key.pem（可另含 key-build / key-build.pub）
#
# 为什么必须固定：rules.mk 里
#   BUILD_KEY_APK_SEC=$(TOPDIR)/private-key.pem   BUILD_KEY_APK_PUB=$(TOPDIR)/public-key.pem
# package/Makefile 在该文件缺失时现场 openssl ecparam -genkey；
# base-files 又把当轮的 public-key.pem 拷进镜像的 /etc/apk/keys/。
# CI 每轮都是新 runner ⇒ 每轮换钥匙 ⇒ 你发布的包仓库只被"同一轮的固件"信任。
#
# 缺 Secret 时这里**故意让构建失败**：静默用临时密钥编出来的固件，
# 以后配自建源必然验签失败，那才是更难查的问题。
#
# 生成方法（本地 Linux/WSL 执行一次，把输出整行贴进 Secret PONWRT_SIGNING_KEYS）：
#   mkdir ponwrt-keys && cd ponwrt-keys
#   openssl ecparam -name prime256v1 -genkey -noout -out private-key.pem
#   openssl ec -in private-key.pem -pubout -out public-key.pem 2>/dev/null
#   tar czf ../keys.tar.gz private-key.pem public-key.pem
#   base64 -w0 ../keys.tar.gz
set -euo pipefail
ROOT="${1:?用法: restore-signing-key.sh <openwrt源码根>}"
cd "$ROOT"
if [ -z "${PONWRT_SIGNING_KEYS:-}" ]; then
	echo "::error::未注入 Secret PONWRT_SIGNING_KEYS"
	echo "        到仓库 Settings → Secrets and variables → Actions 新建"
	echo "        Repository secret 名为 PONWRT_SIGNING_KEYS，值见本文件头部注释。"
	exit 1
fi
printf '%s' "$PONWRT_SIGNING_KEYS" | base64 -d | tar xzf - || { echo "::error::密钥还原失败（不是 tar.gz 的 base64？）"; exit 1; }
chmod 600 private-key.pem key-build 2>/dev/null || true
for f in private-key.pem public-key.pem; do
	[ -s "$f" ] || { echo "::error::$f 缺失"; exit 1; }
done
openssl ec -in private-key.pem -pubout 2>/dev/null | cmp -s - public-key.pem || {
	echo "::error::private-key.pem 与 public-key.pem 不配对"; exit 1; }
echo "✅ 签名密钥已还原，公钥指纹 sha256=$(sha256sum public-key.pem | cut -c1-16)"
echo "   （两轮构建这个指纹必须相同，apk 源才能跨轮更新）"
