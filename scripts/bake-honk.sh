#!/bin/bash
# 把预置的 honk .apk 解出来、放进 files/，从而由标准 rootfs overlay 进镜像。
#   .apk 头是 ADBd（OpenWrt 新版单文件包），tar/gzip 解不了，必须用 apk 工具；
#   apk 工具由 workflow 先单独编：make package/system/apk/host/compile。
#   解包目标是 /tmp 里的一个空 apk root（--initdb），不碰构建中的 rootfs ——
#   中途改 build_dir/root-airoha* 会被 make 的 rootfs 装配步骤重刷掉。
#   放 files/ 才是被构建系统保证复制到镜像的位置。
set -euo pipefail
ROOT="${1:?用法: bake-honk.sh <openwrt源码根>}"
cd "$ROOT"

APK="$(find staging_dir/host/bin -maxdepth 2 -type f -name apk | head -1 || true)"
[ -n "$APK" ] || { echo "::error::没有 host apk 工具；workflow 需先跑 make package/system/apk/host/compile"; exit 1; }
echo "apk 工具: $APK"

MAPKS=(files/etc/apk/local/*.apk)
[ -e "${MAPKS[0]}" ] || { echo "::error::files/etc/apk/local 下没有预置 apk"; exit 1; }
echo "预置 apk: ${#MAPKS[@]} 个"

SCRATCH="$(mktemp -d)/honkroot"
mkdir -p "$SCRATCH/lib/apk/db"
: > "$SCRATCH/lib/apk/db/installed"
mkdir -p "$SCRATCH/etc/apk/keys"
cp -f files/etc/apk/keys/daeuniverse.pem "$SCRATCH/etc/apk/keys/"

# 参数形式照 include/rootfs.mk 的 apk 调用抄：
#   apk --root DIR --keys-dir K --no-logfile --preserve-env add ... \
#       --add-arch all:100 --add-arch $(ARCH_PACKAGES):200
# 两个 arch 都要加：honk 是 aarch64_cortex-a53，luci-app-honk/luci-lib-daeuniverse
# 是 noarch(all)，只给 --arch 一个值会把 all 包判成不匹配。
set +e
out=$(IPKG_INSTROOT="/$SCRATCH" "$APK" --root "/$SCRATCH" \
        --keys-dir "/$SCRATCH/etc/apk/keys" --no-logfile --preserve-env \
        add --initdb \
        --add-arch all:100 --add-arch aarch64_cortex-a53:200 \
        "${MAPKS[@]/#/$ROOT/}" 2>&1)
rc=$?
set -e
printf '%s\n' "$out" | tail -20
if [ "$rc" -ne 0 ]; then
	echo "::error::解包/安装失败 rc=$rc"
	echo "        常见原因：验签不过（公钥不是当前那把）或依赖版本不匹配"
	echo "        （luci-base / ucode 模块名与本基座不同）。上面的输出是原始报错。"
	exit 1
fi

# 只取载荷目录，apk 自己的数据库文件不进镜像
moved=0
for d in usr etc www lib var; do
	if [ -d "$SCRATCH/$d" ]; then
		mkdir -p "files/$d"
		cp -a "$SCRATCH/$d/." "files/$d/"
		moved=$((moved+1))
	fi
done
[ "$moved" -gt 0 ] || { echo "::error::没解出任何载荷目录"; exit 1; }
rm -rf "$(dirname "$SCRATCH")"

# 预置 apk 已完成使命，从镜像里删掉，省 7MB（更新走 @daeuniverse 在线源）
rm -rf files/etc/apk/local

for f in usr/bin/honk-core etc/init.d/honk etc/config/honk etc/honk/config.dae; do
	[ -e "files/$f" ] || { echo "::error::files/ 里缺 $f —— honk 没解出来"; exit 1; }
done
echo "✅ honk 已进 files/ overlay：honk-core $(du -h files/usr/bin/honk-core | cut -f1)、init/UCI/config.dae 齐"
echo "   LuCI 侧: $(ls files/usr/share/luci/menu.d 2>/dev/null | tr '\n' ' ')"
echo "   ucode/rpcd: $(find files/usr/lib -name '*.so' -o -name 'honk*' 2>/dev/null | head -4 | tr '\n' ' ')"
