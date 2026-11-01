#!/bin/bash
# 按 honk-manifest.txt 下载 daeuniverse 的签名 .apk，逐个校验 sha256，
# 放进 <openwrt根>/files/etc/apk/local/ —— 于是它们随 squashfs 进固件，
# 首启由 /etc/uci-defaults/96-honk-bake 离线安装（不需要设备联网）。
#   参数1: openwrt 源码根
#   参数2: 本仓库 ctrl 目录（默认脚本自身所在仓库根）
set -euo pipefail
ROOT="${1:?用法: fetch-honk-apks.sh <openwrt源码根> [ctrl目录]}"
CTRL="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
MANIFEST="$CTRL/honk-manifest.txt"
[ -f "$MANIFEST" ] || { echo "::error::找不到 $MANIFEST"; exit 1; }
DEST="$ROOT/files/etc/apk/local"
mkdir -p "$DEST"
FEED="$(awk -F= '/^HONK_FEED=/{print $2}' "$MANIFEST")"
[ -n "$FEED" ] || { echo "::error::manifest 里没有 HONK_FEED"; exit 1; }
n=0
while IFS='|' read -r name sha; do
	case "$name" in ''|'#'*) continue ;; esac
	url="$FEED/$name"
	echo "→ $name"
	if ! curl -fsSL --retry 3 --max-time 300 -o "$DEST/$name" "$url"; then
		echo "::error::下载失败 $url（版本号被他们 bump 了？更新 honk-manifest.txt）"; exit 1
	fi
	got="$(sha256sum "$DEST/$name" | cut -d' ' -f1)"
	if [ "$got" != "$sha" ]; then
		rm -f "$DEST/$name"
		echo "::error::$name sha256 不匹配 期望=$sha 实得=$got"; exit 1
	fi
	echo "   ✅ sha256 匹配  $(du -h "$DEST/$name" | cut -f1)"
	n=$((n+1))
done < <(grep '|' "$MANIFEST")
[ "$n" -gt 0 ] || { echo "::error::manifest 里没有条目"; exit 1; }
# 他们的仓库公钥必须已在镜像里，否则首启安装会验签失败
[ -s "$ROOT/files/etc/apk/keys/daeuniverse.pem" ] || \
	{ echo "::error::缺 files/etc/apk/keys/daeuniverse.pem，预置 apk 无法验签"; exit 1; }
echo "✅ 已预置 $n 个 honk 相关 apk 到 files/etc/apk/local/"
