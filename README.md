# XG-040G-MD 稳定版构建（Airoha AN7581 / PonWrt）

自己的构建仓库，不是任何人的 fork。只按固定 commit 拉上游源码，
配置 = **上游原样 + 16 个符号的差异**，其余一律继承上游默认值。

设备：诺基亚贝尔 XG-040G-MD · AN7581DT（2×Cortex-A53 + 4 核 NPU）· 512MB RAM · 256MB NAND · 无 WiFi
profile：`nokia_xg-040g-md-ubi` · 架构 `aarch64_cortex-a53` · 包管理 **apk**（没有 opkg）

## 目录

```
pins.env                              锁版本：基座 + 两个 pon feed + 插件源 + 主题 + TYFZA1 端口，全完整 SHA
honk-manifest.txt                     honk 的版本/release 资产/sha256 与 feed SHA（唯一真相）
configs/xg-040g-md.diff.config        与上游的差异（插件 + BTF/eBPF + honk + 主题 + 机型收敛）
scripts/fetch-plugins.sh              按 SHA 取 natmode / pon-status / 主题，断言进索引
scripts/stage-honk.sh                 生成 in-tree honk wrapper 包 + 取 luci-app-honk / luci-lib-daeuniverse 源码
scripts/restore-signing-key.sh        从 Secret 还原固定 apk 签名密钥（缺 Secret 直接失败）
files/etc/apk/repositories.d/         设备上的源：关滚动 snapshot，只留自建 Pages 源
.github/workflows/build.yml           XG-040G-MD（Airoha AN7581）构建 + 断言 + 发 Release + 包仓库上 Pages
.github/workflows/build-tyfza1.yml    天翼 TYFZA1（Realtek RTL9617C）独立构建线
```

## 相对上游只动了这些

`configs/xg-040g-md.diff.config` 追加到上游 `configs/an7581.config` 之后：

- `luci-app-natmode` / `luci-app-pon-status` —— NAT 类型三选一、概览页 PON 光模块卡片
  （温度 / 收光 / 发光 / 偏置电流 / 供电电压）
- `luci-theme-lucent` —— 我自己的主题（保留 bootstrap 兜底）
- `honk` / `luci-app-honk` / `luci-lib-daeuniverse` —— 见下节
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
     除 target 目录外还列了 4 个 feed 源，目录布局与官方 release 一致：
     `@ponwrt-pkg`=packages/…/base、`@ponwrt-luci`=…/luci、`@ponwrt-pon_drivers`、`@ponwrt-pon_userspace`。
     我们的自定义包（honk / natmode / pon-status / lucent）不属于 feed，落在 target 目录，所以走 `@ponwrt`。
     每一条都有「ASSERT package indexes」对照本次真实产出的 `.adb`，写了源却没索引会直接红。

## 构建里的硬断言（任何一条不过就失败，不出"看起来成功"的残缺固件）

1. `.config` 必须含 `DEBUG_INFO_BTF=y` / `REDUCED is not set` / `DWARVES=y` / ftrace / 关键 PON 包 /
   两个 LuCI 插件；且 `python3|ruby|perl` **不得**被选中
2. `luci-app-natmode`、`luci-app-pon-status` 必须在 `tmp/.packageinfo` 里
3. 插件源、两个 pon feed、主题、daeuniverse feed 的实际 checkout SHA 必须等于锁定值
4. 公钥由私钥现场导出（跨 OpenSSL 版本比 PEM 文本会误判），并打印指纹供跨轮比对
5. 编完后 `readelf -S vmlinux` 必须能看到 `.BTF` 段
6. **成品包列表以 rootfs 的 `lib/apk/db/installed` 为准**，不是 manifest 文本：
   manifest 是 SoC 级汇总（不含机型专属 `kmod-airoha-en7572`），且 C++ 运行时在包库里
   叫 `libstdc++` 而不是符号名 `libstdcpp` —— 两种写法都错过一次
7. 加进 `package/custom/` 的包，Makefile 文本里必须有 `call BuildPackage` 字样：
   `include/scan.mk` 是静态 grep 决定"这个目录算不算包"，`luci.mk` 里那句它看不见；
   缺标记 = 静默不索引、不报错、没有 `logs/` 痕迹（我的主题就是这么丢的）

## honk 已编进固件（in-tree 包）

`scripts/stage-honk.sh` 按 `honk-manifest.txt` 生成三个真包，`CONFIG_PACKAGE_*=y` 选中后
和普通包一样编进 rootfs、进 apk 数据库、可 `apk info` / `apk upgrade`：

| 包 | 内容来源 | 说明 |
|---|---|---|
| `honk` | honk 官方 release 资产 `honk-core-v0.1.0-beta.4-aarch64-unknown-linux-musl-full.tar.gz` | **静态链接 ELF**（内嵌 doona / doona-lite 面板），下载与 `PKG_HASH` 校验由 buildroot 做；hash 与 release 附带的 `SHA256SUMS` 逐字核对过 |
| `honk` 的 `init/UCI/config.dae` | `daeuniverse/openwrt-packages@503cdb13` 的 `honk/files/` | 112 行 procd 脚本，自己处理 bpffs 与 cgroup memory 控制器 |
| `luci-app-honk` / `luci-lib-daeuniverse` | 同一 feed 同一 SHA 的源码 | 后者带 `po/` 中文，依赖 `jshn` / `flock` / `coreutils-timeout` |

为什么不源码编译、也不解他们的 `.apk`：源码要 pinned nightly Rust + 预编译 `bpf-linker`
+ BoringSSL(Go)，而那个 feed 仓库里没有这套 CI 定义；他们的 `.apk` 头是 `ADBd`（新版单文件
格式），`tar`/`gzip` 打不开，用构建里的 host `apk` 解又被 `package/utils/lua[host]` 编不过挡住。
取官方 release 二进制是这条路里唯一"无编译依赖、可校验、结果确定"的做法。

因为是静态二进制，**不需要 `libstdcpp`**；内核模块与 geodata 仍按运行期需要带着
（`kmod-veth/sched-core/sched-bpf/nft-core/nft-queue/nfnetlink-queue/nf-conntrack`
+ `v2ray-geoip` / `v2ray-geosite`）。BTF 由本固件自己提供，不依赖 `vmlinux-btf` blob。

两点要知道：

- **服务默认不开**（他们的包本来就这样）。honk 会挂 TC/cgroup `sock_ops`、改 sysctl、
  占 NFQUEUE 320，配好节点和分流之前别启动 —— 这是避免把正在用的网络掐掉。
  确认 dropbear 还能进之后再 `/etc/init.d/honk enable && start`。
- 他们 bump 版本后 release 资产 URL 或 hash 变了，buildroot 下载/校验会直接失败，
  不会静默少装；升级 = 改 `honk-manifest.txt` 里的版本与 sha256。
- 也可以直接吃他们的在线源：镜像内置 `@daeuniverse`
  （`files/etc/apk/repositories.d/daeuniverse.list`，公钥 `files/etc/apk/keys/daeuniverse.pem`，
  sha256 钉在 manifest，构建时与锁定 feed 里那份逐字节核对）。装出来的同名包会由 apk 正常接管
  并登记数据库：`apk update && apk add --force honk@daeuniverse`。
  他们的 `kmods/…` 那行**故意不写**：那是给他们自己编的内核用的，且我们这个机型是 404。
  URL 里版本号写死 `25.12` —— PonWrt 的 `DISTRIB_RELEASE` 是 `SNAPSHOT`，照官网那条命令拼必 404。

内核前提已满足：构建会断言 `vmlinux` 含 `.BTF`，设备上 `ls /sys/kernel/btf/vmlinux`
应有文件；`bpffs` 由 base-files 的 `/etc/init.d/boot` 自动挂载。
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
