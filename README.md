# OnePlus 9 Pro (LE2121) Droidspaces 内核源码仓库

自包含内核源码仓库：clone 后可**离线**编译出带 Droidspaces 完整内核能力的内核 `Image`。

> **重要：本仓库不收录原厂 `boot.img`。**
> 原厂 boot 镜像约 192MB，超过 GitHub 单文件 100MB 限制，因此已从版本库排除。
> 若要让 `./build.sh` 直接打包出可刷写的 `boot_new.img`，需**自行准备原厂 boot 镜像**
> 并放到 `boot/boot_b.img`（见「准备原厂 boot 镜像」）。
> 未提供该文件时仍可正常编译内核 `Image`，脚本会跳过打包并给出提示。

## 设备与目标

- 设备：OnePlus 9 Pro 印度版 **LE2121**（骁龙 888 / lahaina / sm8350）
- 系统：Oxygen OS 14（UKQ1.230924.001）
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

## 关键设计说明

1. **config 基线**：编译用 `config/build.config`，它源自设备真实 `/proc/config.gz`，
   只最小启用了 Droidspaces 必需项（SYSVIPC/POSIX_MQUEUE/PID_NS/IPC_NS/USER_NS/
   DEVTMPFS/OVERLAY_FS/netfilter/ipset 等），禁项 CFS_BANDWIDTH/CGROUP_PIDS 保持 off。
2. **kABI 兼容**：module_layout 与 2075 个内核导出符号 CRC 与原厂 vendor 模块全部匹配，
   保证 WiFi/显示/触控等厂商模块可加载。校验：`python3 scripts/check_symvers_vs_device.py out/Module.symvers config/device_symbol_crcs.tsv`
3. **AVB**：刷写 boot 分区需配合禁用 AVB 校验的 vbmeta（无 OEM 私钥无法重签），
   或使用 Kernel Flasher 的 AnyKernel3 包（自动 patch vbmeta）。临时验证用 `fastboot boot` 不涉及校验。
4. **适用范围**：仅限 LE2121 Oxygen OS 14，**不可**用于国行 ColorOS（LE2120）或其他机型/ROM——
   ramdisk、vendor 模块 CRC、AVB 密钥均与具体 ROM 深度绑定。

## 已验证状态（2026-11-22 实机）

- 编译成功，uname = `5.4.254-qgki-gd2a1055adeb0`
- kABI：module_layout 匹配，2075 符号 0 CRC 漂移
- 真机启动：修补内核 + APatch root 正常进系统，SELinux Enforcing
- Droidspaces 所需内核能力全部齐备（命名空间/IPC/cgroup/网络/overlayfs，命令 unshare/nsenter/ip）
