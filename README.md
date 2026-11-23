# OnePlus 9 Pro Droidspaces 内核源码仓库

自包含内核源码仓库：clone 后可**离线**编译出带 Droidspaces 完整内核能力的内核 `Image`。

该内核镜像适用于 **OnePlus 9 Pro 全系机型**（LE2120 / LE2121 / LE2123 / LE2125 / LE2127，
OxygenOS 与 ColorOS 均可），前提是目标系统同为 GKI `android12-5.4` / `5.4.254-qgki` KMI。
Droidspaces 依赖的全部是编译期内核配置开关，编进 `Image` 后即与上层 ROM 无关——
**只要内核能启动，Droidspaces 就能用**。详见「适用范围与跨 ROM 说明」。

> **重要：本仓库不收录原厂 `boot.img`。**
> 原厂 boot 镜像约 192MB，超过 GitHub 单文件 100MB 限制，因此已从版本库排除。
> 若要让 `./build.sh` 直接打包出可刷写的 `boot_new.img`，需**自行准备原厂 boot 镜像**
> 并放到 `boot/boot_b.img`（见「准备原厂 boot 镜像」）。
> 未提供该文件时仍可正常编译内核 `Image`，脚本会跳过打包并给出提示。

## 设备与目标

- 设备：OnePlus 9 Pro 全系（骁龙 888 / lahaina / sm8350）；**LE2121 印度版为编译与实机验证基准**，
  编译产物 `Image` 亦可用于 LE2120/21/23/25/27 的同 KMI 系统（见「适用范围与跨 ROM 说明」）
- 系统：Oxygen OS 14（UKQ1.230924.001，验证基准）
- 内核：**5.4.254-qgki-gd2a1055adeb0**（KMI/GKI `android12-5.4`，简称 GKI-5.4.254）
- 目标：在 Stock 内核基础上最小启用 Droidspaces 所需配置（容器/命名空间/cgroup/netfilter），
  保持 kABI 与厂商 vendor 模块 CRC 兼容，不关闭 SELinux。

## 准备原厂 boot 镜像（生成 boot.img 必需）

`./build.sh` 打包 `boot_new.img` 时以原厂 boot 为模板，**字节级保留其 ramdisk 与 boot header**，
只替换内核。请从**本机同 ROM、同 slot** 提取原厂 boot（务必先备份，勿跨机型/跨 ROM 使用）：

```bash
# 设备已 root，adb 已连接；boot_b 对应 slot B，若当前在 slot A 则改用 boot_a
adb shell su -c 'dd if=/dev/block/by-name/boot_b of=/sdcard/boot_b.img bs=4M'
adb pull /sdcard/boot_b.img boot/boot_b.img
```

也可从 OOS14 全量包 / 官方固件中解出 `boot.img`。放置后校验大小约 192MB。

- 若**不需要**打包 boot 镜像（例如只做内核编译、或用 Kernel Flasher / AnyKernel3 刷入编译产物），
  可跳过此步，`./build.sh` 仍会产出 `out/arch/arm64/boot/Image` 与 `modules`。
- 原厂 boot 属于设备备份文件，请勿提交到版本库（已由 `.gitignore` 排除）。

## 快速开始

```bash
# 0) 可选：准备原厂 boot 镜像（要生成可刷写的 boot_new.img 时才需要，见上节）

# 1) 查看帮助
./build.sh --help

# 2) 一键编译 + 打包出 boot.img
./build.sh

# 产出：
#   out/arch/arm64/boot/Image   编译内核二进制
#   boot_new.img                修补内核的 boot 镜像（ramdisk 保留原厂；缺少原厂 boot 时不生成）

# 3) 清理编译产物（保留源码、工具链，以及你自行放置的 boot/boot_b.img）
./build.sh clean
```

- 编译约 20-30 分钟（取决于 CPU），日志写在 `build.log`。
- `build.sh` 参数：`--help`(`-h`/`help`) 显示帮助；`clean` 删除 `out/`、`boot_new.img`、`build.log`。
  更多操作可用 `make image` / `make kabi` / `make clean` / `make help`。
- `boot_new.img` 是**未 root** 的修补内核镜像；要临时验证：
  `fastboot boot boot_new.img`（不写分区，重启失效）。

## 目录结构

```
.
├── build.sh                 一键编译+打包脚本（入口）
├── Makefile                 make 快捷入口
├── README.md                本文件
├── LICENSE                  GPL-3.0
├── src/kernel_src/          内核源码树（已应用 Droidspaces 补丁，含 .scmversion 固定 uname）
│                            119 个软链指向 ../vendor/ 与 ../kernel/msm-5.4
├── vendor/                  一加厂商内核源码补全（mndtv14/vendor，264M，软链目标）
├── vendor_kernel/           一加厂商 techpack 补全（mndtv14/kernel，47M）
├── kernel/msm-5.4 -> ../src/kernel_src   （满足源码内 techpack 软链 ../../kernel/msm-5.4）
├── toolchain/
│   ├── clang/               AOSP clang-r383902b1（build 6877366 / 11.0.2，与设备精确匹配，1.1G）
│   └── aarch64/bin/         aarch64-linux-gnu-* 包装软链（相对路径，指向 clang）
├── config/
│   ├── build.config         设备 /proc/config.gz 基线 + Droidspaces 最小改动（实际编译用 .config）
│   ├── device.config        设备原始完整 config
│   └── device_symbol_crcs.tsv  厂商 vendor 模块符号 CRC 基准（kABI 校验用）
├── patches/                 Droidspaces / KABI 补丁（003/004 已应用；001/002 不适用未应用）
├── scripts/                 编译/校验/打包脚本
│   ├── repack_boot.py       boot 镜像重打包（仅替换 kernel）
│   ├── apply_droidspaces_config.py   从 device.config 生成 build.config
│   ├── check_symvers_vs_device.py    kABI/CRC 校验
│   ├── verify_kabi.py / fix_build_env.sh / build_kernel_v2.sh
└── boot/                    （目录内文件不纳入版本库）
    └── boot_b.img           原厂 boot_b：需自行准备，提供 ramdisk，打包时字节级保留
```

## 源码来源与许可

- 内核主线源码：`https://github.com/OnePlusOSS/android_kernel_oneplus_sm8350.git`
  commit `9e38a9fabb4de096bf386b7be988b7f7c5e4c58e`（OOS14 内核）。
- 厂商补全：OnePlusOSS `android_kernel_modules_and_devicetree_oneplus_sm8350`
  分支 `oneplus/sm8350_u_14.0.0_oneplus9`（提供 vendor/ 与 techpack）。
- 工具链：AOSP clang-r383902b1（LLVM 11.0.2），与设备内核编译工具链精确一致。
- 遵循各自上游开源许可（GPL-2.0 等）；本仓库附加说明采用 GPL-3.0。

## 适用范围与跨 ROM 说明

「内核」需要分两层看，结论不同：

| 层次 | 是否通用 | 说明 |
|---|---|---|
| 内核源码树 `android_kernel_oneplus_sm8350` | 全系通用 | LE2120/21/23/25/27 同为 sm8350/lahaina，一加只维护一份源码（OOS14 与国行 ColorOS 14 同属 `oneplus/sm8350_u_14.0.0_oneplus9` 分支） |
| 编译产物 `Image`（内核二进制） | 同 KMI 通用 | Droidspaces 全是 `.config` 编译期开关，编进 `Image` 后与 ROM 无关；只要目标系统同为 `android12-5.4` / `5.4.254-qgki`，可直接复用，无需重新编译 |
| 完整 `boot.img` | 不通用 | = kernel + ramdisk + dtbo + AVB 签名链，后三项由具体 ROM / 区域绑定 |

**核心判定**：Droidspaces 依赖的 SYSVIPC / POSIX_MQUEUE / PID_NS / IPC_NS / USER_NS /
DEVTMPFS / OVERLAY_FS / netfilter / ipset / macvlan / cgroup2 等，全部是**编译进内核**的
能力，不是开机时从 ROM 读取的配置。因此判定链只有一环：

> **内核成功启动 => Droidspaces 能力恒在 => Droidspaces 可用**

上层是 OxygenOS、ColorOS 还是第三方 ROM，不影响这一判定。

### 推荐刷法：只替换 kernel

跨 ROM 使用请走「只刷内核」的方式（Kernel Flasher / AnyKernel3 / `scripts/repack_boot.py`）：
拆目标机**自己的**原厂 boot，保留其 ramdisk 与 dtbo，**只替换 kernel**。
这样 ramdisk 天然与目标 ROM 匹配，不会串用本仓库基于 OOS14 打包的 `boot_new.img`。

> 不要把 `boot_new.img`（或 OOS14 整包）直接刷到 ColorOS —— 它的 ramdisk 和签名链是 OOS 的。

### 三道门槛属于「能否开机」，不属于「Droidspaces 能否用」

| 门槛 | 归属 | 处理 |
|---|---|---|
| ramdisk / dtbo | 能否开机 | 只换 kernel、保留目标机 ramdisk 即自动规避 |
| vendor 模块 CRC | 能否开机 | 同 KMI 大概率一致（OOS14 实测 2075 符号 0 漂移）；跨 ROM 建议对目标 `vendor_dlkm` 重跑 `check_symvers_vs_device.py` |
| AVB / vbmeta | 能否开机 | 需 `--disable-verity --disable-verification` 刷对应 vbmeta（chain descriptor 需 OEM 私钥） |

万一卡在开机 logo，属上述签名链 / vendor 模块配合问题，**与 Droidspaces 能力无关**，
换用目标 ROM 的 ramdisk 重打包并处理 vbmeta 即可。

> 说明：跨 ROM 复用是基于同机型、同 KMI、同一源码分支的核对结论；
> 本仓库的**实机验证仅在 LE2121 / OxygenOS 14 上完成**，ColorOS 尚未实机验证。

## 关键设计说明

1. **config 基线**：编译用 `config/build.config`，它源自设备真实 `/proc/config.gz`，
   只最小启用了 Droidspaces 必需项（SYSVIPC/POSIX_MQUEUE/PID_NS/IPC_NS/USER_NS/
   DEVTMPFS/OVERLAY_FS/netfilter/ipset 等），禁项 CFS_BANDWIDTH/CGROUP_PIDS 保持 off。
2. **kABI 兼容**：module_layout 与 2075 个内核导出符号 CRC 与原厂 vendor 模块全部匹配，
   保证 WiFi/显示/触控等厂商模块可加载。校验：`python3 scripts/check_symvers_vs_device.py out/Module.symvers config/device_symbol_crcs.tsv`
3. **AVB**：刷写 boot 分区需配合禁用 AVB 校验的 vbmeta（无 OEM 私钥无法重签），
   或使用 Kernel Flasher 的 AnyKernel3 包（自动 patch vbmeta）。临时验证用 `fastboot boot` 不涉及校验。
4. **适用范围**：内核 `Image` 适用于 OnePlus 9 Pro 全系同 KMI 机型与 ROM；
   完整 `boot.img` 的 ramdisk / vendor CRC / AVB 与具体 ROM 绑定，跨 ROM 需「只替换 kernel」重打包。
   详见「适用范围与跨 ROM 说明」。

## Root 方案与容器稳定性（实机对比）

Root 注入层与 Droidspaces 内核能力是**互相独立的两层**：本仓库产出的 `Image` 已经包含
Droidspaces 所需全部编译期配置，Root 方案只决定「如何取得 su」，不需要也不应该为此改动
内核 config 或 kABI。

### 实测结论（LE2121 / OOS14）

| Root 方案 | 对内核 `Image` 的影响 | Droidspaces 容器运行表现 | 结论 |
|---|---|---|---|
| **Magisk** | 零改动，仅 patch boot 的 ramdisk | **最稳定**，实测容器各项功能正常 | **首选** |
| APatch / KernelPatch | patch 内核 Image，需重新打包 boot | 可 root、可正常进系统；容器运行稳定性不如 Magisk | 备选 |
| KernelSU-Next | 需将驱动编入内核并加 kABI guard | 5.4 上曾显示「未集成」，且维护成本最高 | 当前 `main` 分支未集成 |

> 结论来自实机对三种 Root 方案的容器运行对比：**只有 Magisk 表现最稳定**。
> 因此推荐用 Magisk 获得 Root，不要为了 Root 改动内核配置。

### 推荐流程（Magisk）

1. 先取得未 root 的 boot：直接 `./build.sh` 产出 `boot_new.img`，或跨 ROM 时按
   「推荐刷法：只替换 kernel」为目标机自己的原厂 boot 重打包。
2. 用 Magisk 对该 boot 做 patch，刷回对应 slot（`fastboot flash boot_a` / `boot_b`）。
3. 保持已禁用校验的 vbmeta 状态（刷新 boot 不需要恢复 AVB；无 OEM 私钥也无法重签）。
4. 开机后确认 `su`、`getenforce`（保持 Enforcing）、`uname -r` 及 Droidspaces Requirements。
5. 以后每次重新编译内核，只需对新 boot 重新做一次 Magisk patch；内核 config 无需为 Root 调整。

### 注意事项

- 切换 Root 方案前先清掉旧方案（APatch 内核 patch / KSU 模块），避免两套 Root 冲突。
- 容器网络只有 `127.0.0.1` 属于运行时 NAT 层问题，不是 Root 方案或内核配置缺项；
  先确认 Droidspaces Net 模式为 `NAT`，再排查宿主 `ip_forward` 与 `iptables` MASQUERADE 规则。

## 已验证状态（2026-11-22 ~ 11-23 实机）

- 编译成功，uname = `5.4.254-qgki-gd2a1055adeb0`
- kABI：module_layout 匹配，2075 符号 0 CRC 漂移
- 真机启动：修补内核 + APatch root 正常进系统，SELinux Enforcing
- Droidspaces 所需内核能力全部齐备（命名空间/IPC/cgroup/网络/overlayfs，命令 unshare/nsenter/ip）
- Root 方案对比（11-23）：Magisk 的容器运行最稳定，作为推荐方案；APatch 可 root 但容器表现次之
