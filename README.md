# XG-040G-MD 稳定版构建（Airoha AN7581 / PonWrt）

自己的构建仓库，不是任何人的 fork。只按固定 commit 拉上游源码，
配置 = **上游原样 + 16 个符号的差异**，其余一律继承上游默认值。

设备：诺基亚贝尔 XG-040G-MD · AN7581DT（2×Cortex-A53 + 4 核 NPU）· 512MB RAM · 256MB NAND · 无 WiFi
profile：`nokia_xg-040g-md-ubi` · 架构 `aarch64_cortex-a53` · 包管理 **apk**（没有 opkg）

## 目录

```
pins.env                              锁版本：基座 + 两个 pon feed + 插件源，全部完整 SHA
configs/xg-040g-md.diff.config        与上游的差异（2 个 LuCI 包 + BTF/eBPF 段）
scripts/fetch-plugins.sh              按 SHA 取 luci-app-natmode / luci-app-pon-status，并断言进索引
scripts/restore-signing-key.sh        从 Secret 还原固定 apk 签名密钥（缺 Secret 直接失败）
files/etc/apk/repositories.d/         设备上的源：关滚动 snapshot，留自建源 + daeuniverse
files/etc/apk/keys/daeuniverse.pem    honk 源的公钥
.github/workflows/build.yml           构建 + 断言 + 发 Release + 发包仓库到 Pages
```

## 相对上游只动了这些

`configs/xg-040g-md.diff.config` 追加到上游 `configs/an7581.config` 之后：

- `luci-app-natmode` / `luci-app-pon-status` —— NAT 类型三选一、概览页 PON 光模块卡片
  （温度 / 收光 / 发光 / 偏置电流 / 供电电压）
- BTF 段：`CONFIG_KERNEL_DEBUG_INFO_BTF=y`、**`# CONFIG_KERNEL_DEBUG_INFO_REDUCED is not set`**、
  `CONFIG_KERNEL_MODULE_ALLOW_BTF_MISMATCH=y`、ftrace 三项、
  `kmod-sched-core/sched-bpf/nft-queue/nfnetlink-queue`

PON 驱动与用户态（`kmod-airoha-xpon`、`kmod-airoha-pon-frontend`、`kmod-airoha-en7572`、
`airoha-pond`、`airoha-ponctl`、`luci-app-pon` + 中文、`kmod-nft-fullcone`、
`CONFIG_LUCI_LANG_zh_Hans`、`flow_offloading_hw=1` + `fullcone=1`）
**上游基座本来就 =y**，这里不重复声明。

不需要 libffi/python3 那类补丁：上游 `package/libs/libffi` 存在，且本配置不选 python3
（构建里有一道反向断言，python3/ruby/perl 被拖进来就失败）。

## REDUCED 那行为什么是关键

`config/Config-kernel.in`：

```
config KERNEL_DEBUG_INFO_BTF
	depends on KERNEL_DEBUG_INFO && !KERNEL_DEBUG_INFO_REDUCED
	select DWARVES
```

上游基座写的是 `CONFIG_KERNEL_DEBUG_INFO_REDUCED=y`。不显式关掉它，`make defconfig`
会把 BTF **静默剔除**，编出来的内核没有 `/sys/kernel/btf/vmlinux`，honk 拒绝启动。
关掉后 `select DWARVES` 自动把 `tools/dwarves`（pahole 1.31）编成 host 工具。
这个组合与 ImmortalWrt 官方 filogic 快照 `config.buildinfo` 完全一致。

## 怎么构建

1. Settings → Secrets and variables → Actions → 新建 repository secret
   `PONWRT_SIGNING_KEYS`，值按 `scripts/restore-signing-key.sh` 头部注释生成（**一次生成，长期不换**，
   否则每轮换钥匙，自建源跨轮验签会失败）。
2. Settings → Pages 不用手开，workflow 里有一步尝试启用（源 `gh-pages`）。
3. Actions → **build-xg040gmd** → Run workflow：
   - `source_sha` 留空 = 用 `pins.env` 的锁定版本（可复现）；填 SHA = 临时升级
   - `publish_repo` = `true` 才会把包仓库推到 Pages
4. 产物：
   - 固件：Releases 里固定滚动 tag **`stable-xg040gmd`**
   - 包仓库：`https://<owner>.github.io/<repo>/targets/airoha/an7581/packages/packages.adb`
     （设备里已预置成 `@ponwrt`，`apk update && apk upgrade` 只认你自己这套）

## 构建里的硬断言（任何一条不过就失败，不出"看起来成功"的残缺固件）

1. `.config` 必须含 `DEBUG_INFO_BTF=y` / `REDUCED is not set` / `DWARVES=y` / ftrace / 关键 PON 包 /
   两个 LuCI 插件；且 `python3|ruby|perl` **不得**被选中
2. `luci-app-natmode`、`luci-app-pon-status` 必须在 `tmp/.packageinfo` 里
3. 插件源、两个 pon feed 的实际 checkout SHA 必须等于 `pins.env`
4. `public-key.pem` 必须与 `private-key.pem` 配对，并打印指纹（跨轮应一致）
5. 编完后 `readelf -S vmlinux` 必须能看到 `.BTF` 段

## honk 不进固件（故意的）

它是 `v0.1.0-beta.4`，作者自己标 alpha/beta 不建议生产，还会改 TC/cgroup/sysctl、占 NFQUEUE 320。
装法（源和公钥已预置）：

```sh
apk update && apk add honk@daeuniverse luci-app-honk@daeuniverse
ls -l /sys/kernel/btf/vmlinux && mountpoint /sys/fs/bpf
```

出问题回滚：`/etc/init.d/honk stop; apk del honk luci-app-honk`（dropbear 是带外通道，别删）。
注意 `flow_offloading_hw=1`（NPU/PPE 硬件卸载）默认开着——**代理分流若漏走或 NAT 类型不符，
先把它设 0 做对比**：`uci set firewall.@defaults[0].flow_offloading_hw='0'; /etc/init.d/firewall restart`。

## 刷之前

**必须先用 <https://github.com/pbs05/an758x-stock2ubi> 全分区备份原厂 flash**，
特别是 `mtd6-BOSA` / `mtd7-RI`（每机唯一的激光校准 + SN/MAC；丢了刷回别人的备份也救不回来）。
免拆脚本可用 <https://github.com/traceless/an758x-ont-autoflash>（自动备份 bosa+ri）。
U-Boot：<https://github.com/pbs05/uboot-an758x> → 断电重上电数 3 秒长按 reset 到某 LAN 灯连闪 5 次
→ `http://192.168.1.1` 上传 `*-squashfs-sysupgrade.itb`。
首启后 `网络 → PON → 配置 → PON board data` 恢复校准数据，再填 LOID/SN/MAC/VLAN。
线路要求：本机型光模块是 **XG-PON**（驱动侧 GPON ❌、XGS-PON ❓）。
