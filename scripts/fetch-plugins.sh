#!/bin/bash
# 拉两个 LuCI 插件到 <openwrt根>/package/custom，并确认它们进了包索引。
#   参数1: openwrt 源码根
#   环境变量: LUCI_APP_URL / LUCI_APP_SHA（由 workflow 从 pins.env 注入）
# 任何一步不对都直接 exit 1 —— 上一次构建就是因为脚本被 || true 吞掉，
# 静默出了个"少了功能但看不出来"的结果。
set -euo pipefail
ROOT="${1:?用法: fetch-plugins.sh <openwrt源码根>}"
: "${LUCI_APP_URL:?未设置 LUCI_APP_URL}"
: "${LUCI_APP_SHA:?未设置 LUCI_APP_SHA}"
cd "$ROOT"
PKG_DIR="package/custom"
mkdir -p "$PKG_DIR"
TMP="$(mktemp -d)/luci-app"
git init -q "$TMP"
git -C "$TMP" remote add origin "$LUCI_APP_URL"
git -C "$TMP" fetch -q --depth 1 origin "$LUCI_APP_SHA"
git -C "$TMP" checkout -q FETCH_HEAD
echo "插件源 = $(git -C "$TMP" rev-parse --short HEAD)（期望 ${LUCI_APP_SHA:0:7}）"
[ "$(git -C "$TMP" rev-parse HEAD)" = "$LUCI_APP_SHA" ] || { echo "::error::插件源 SHA 不匹配"; exit 1; }
for p in luci-app-natmode luci-app-pon-status; do
	[ -f "$TMP/$p/Makefile" ] || { echo "::error::$p/Makefile 不存在（上游改结构了？）"; exit 1; }
	rm -rf "$PKG_DIR/$p"
	cp -a "$TMP/$p" "$PKG_DIR/"
	echo "✅ 已放置 $p  版本 $(grep -m1 '^PKG_VERSION' "$PKG_DIR/$p/Makefile" | cut -d= -f2)"
done
# ---- 我写的主题：仓库根目录本身就是包（Makefile 在根，PKG_NAME=luci-theme-lucent）----
# 目录名必须等于包名（buildroot: PKG_NAME ?= $(notdir ${CURDIR})），否则符号对不上。
# 处理和上面两个插件完全一致：clone 到临时目录再 cp -a，不把 .git 留在 package/ 里
# （上一轮原地 git init 时，主题 Makefile 正常但 dump 失败、进不了 .packageinfo）。
: "${THEME_URL:?未设置 THEME_URL}"
: "${THEME_SHA:?未设置 THEME_SHA}"
THEME_TMP="$(mktemp -d)/lucent"
git init -q "$THEME_TMP"
git -C "$THEME_TMP" remote add origin "$THEME_URL"
git -C "$THEME_TMP" fetch -q --depth 1 origin "$THEME_SHA"
git -C "$THEME_TMP" checkout -q FETCH_HEAD
[ "$(git -C "$THEME_TMP" rev-parse HEAD)" = "$THEME_SHA" ] || { echo "::error::主题源 SHA 不匹配"; exit 1; }
[ -f "$THEME_TMP/Makefile" ] || { echo "::error::主题缺 Makefile"; exit 1; }
rm -rf "$PKG_DIR/luci-theme-lucent"
cp -a "$THEME_TMP" "$PKG_DIR/luci-theme-lucent"
rm -rf "$(dirname "$THEME_TMP")"
echo "✅ 已放置 luci-theme-lucent  @ ${THEME_SHA:0:7} 版本 $(grep -m1 '^PKG_VERSION' "$PKG_DIR/luci-theme-lucent/Makefile" | cut -d= -f2)"
# 重建索引：只删 .packageinfo 不够，prepare-tmpinfo 有 scan_unchanged 的 stamp 优化，
# stamp 还在就跳过扫描，结果索引被删了却没人重建。stamp 必须一起删。
rm -f tmp/.packageinfo tmp/.targetinfo tmp/info/.scan-packageinfo.stamp tmp/info/.scan-targetinfo.stamp
make -s prepare-tmpinfo OPENWRT_BUILD= >/dev/null 2>&1 || true
for p in luci-app-natmode luci-app-pon-status luci-theme-lucent; do
	if ! grep -qx "Package: $p" tmp/.packageinfo; then
		echo "::error::$p 没进 tmp/.packageinfo，defconfig 会静默剔除"
		# buildroot 扫描失败的具体原因在这个文件里，不打出来就只能猜
		for f in "logs/package/$p/dump.txt" "logs/package/custom/$p/dump.txt"; do
			[ -f "$f" ] && { echo "----- $f -----"; tail -20 "$f"; }
		done
		exit 1
	fi
	echo "✅ 索引确认: $p"
done
