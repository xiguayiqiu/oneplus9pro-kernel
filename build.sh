#!/usr/bin/env bash
# OnePlus 9 Pro (LE2121) Droidspaces 内核一键编译脚本
# 用法: ./build.sh [--help | clean | --quiet]
#   无参数          编译内核并打包出 boot_new.img (默认实时显示 make 输出)
#   --help, -h      显示帮助
#   clean           清理编译产物 (out/、boot_new.img、build.log)
#   --quiet, -q     不实时显示 make 输出 (仍完整写入 build.log)
# 产出: out/arch/arm64/boot/Image  +  boot_new.img (可 fastboot flash 的 boot 镜像)
set -uo pipefail

# 清除可能注入的 rm/cp/mv 函数(会把命令重定向到无权限 shim,导致内核 Makefile 的 rm -f 失败)
unset -f rm cp mv 2>/dev/null || true

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/src/kernel_src"
OUT="$ROOT/out"
CL="$ROOT/toolchain/clang/bin"
TC="$ROOT/toolchain/aarch64/bin"
CONFIG="$ROOT/config/build.config"
ORIG_BOOT="$ROOT/boot/boot_b.img"
GKI_VER="GKI-5.4.254"

usage() {
    cat <<'EOF'
用法: ./build.sh [命令]

命令:
  (无参数)          编译内核并打包出 boot_new.img，实时显示 make 输出
  --help, -h, help  显示本帮助
  clean             清理编译产物 (out/、boot_new.img、build.log)，保留源码与工具链
  --quiet, -q       不实时显示 make 输出，仅写入 build.log

更多操作可用 make: make image / make kabi / make clean
EOF
}

LIVE_LOG=1
case "${1:-}" in
  --quiet|-q)
    LIVE_LOG=0
    shift
    ;;
esac

case "${1:-}" in
  --help|-h|help)
    usage
    exit 0
    ;;
  clean)
    rm -rf "$OUT" "$ROOT/boot_new.img" "$ROOT/build.log"
    echo "已清理编译产物: $OUT、$ROOT/boot_new.img、$ROOT/build.log"
    exit 0
    ;;
  "")
    ;;
  *)
    echo "未知参数: $1" >&2
    usage >&2
    exit 1
    ;;
esac

mkdir -p "$OUT"
echo "=== 构建开始 $(date) ==="
echo "仓库: $ROOT"
echo "源码: $SRC"
echo "工具链: $("$CL/clang" --version | head -1)"
echo "期望 uname: 5.4.254-qgki-gd2a1055adeb0"

# 步骤1: 放置 .config (使用设备 /proc/config.gz 基线 + Droidspaces 最小改动)
if [ -f "$CONFIG" ]; then
    cp "$CONFIG" "$OUT/.config"
    echo "已载入 config: $CONFIG"
else
    echo "缺少 $CONFIG"; exit 1
fi

cd "$SRC" || exit 1

# 步骤2: 编译 (参数与已验证成功的 build_kernel_v2.sh 完全一致,仅路径改为仓库内相对)
echo "=== 编译 (make -j) ==="
: > "$ROOT/build.log"
TAIL_PID=""
cleanup_tail() {
    if [ -n "$TAIL_PID" ]; then
        kill "$TAIL_PID" 2>/dev/null || true
        wait "$TAIL_PID" 2>/dev/null || true
        TAIL_PID=""
    fi
}
trap cleanup_tail EXIT

if [ "$LIVE_LOG" -eq 1 ]; then
    echo "实时输出来自 $ROOT/build.log (Ctrl+C 可中断编译)"
    tail -n +1 -f "$ROOT/build.log" &
    TAIL_PID=$!
fi

env -u BASH_ENV -u 'BASH_FUNC_rm%%' -u 'BASH_FUNC_cp%%' -u 'BASH_FUNC_mv%%' \
    -u 'BASH_FUNC_ln%%' -u 'BASH_FUNC_mkdir%%' \
    PATH="$TC:$CL:/usr/bin:/bin" \
    make ARCH=arm64 O="$OUT" \
    CROSS_COMPILE=aarch64-linux-gnu- \
    CLANG_TRIPLE=aarch64-linux-gnu- \
    LLVM_IAS=1 \
    CC="$CL/clang" LD="$CL/ld.lld" AS="$CL/clang" \
    AR="$CL/llvm-ar" NM="$CL/llvm-nm" \
    OBJCOPY="$CL/llvm-objcopy" OBJDUMP="$CL/llvm-objdump" \
    READELF="$CL/llvm-readelf" STRIP="$CL/llvm-strip" \
    -j8 Image modules </dev/null >>"$ROOT/build.log" 2>&1
RC=$?
cleanup_tail

if [ ! -f "$OUT/arch/arm64/boot/Image" ] || [ ! -f "$OUT/Module.symvers" ]; then
    RC=1
fi
echo "=== make 退出码: $RC ==="
if [ "$RC" -ne 0 ]; then
    echo "编译失败,详见 build.log"; exit "$RC"
fi

echo "=== 产物 ==="
ls -lh "$OUT/arch/arm64/boot/Image" "$OUT/vmlinux" "$OUT/System.map" "$OUT/Module.symvers"
echo "编译出的 uname: $(cat "$OUT/include/config/kernel.release" 2>/dev/null)"

# 步骤3: 打包 boot.img (仅替换 kernel, 保留原 ramdisk/header)
echo "=== 打包 boot.img ==="
if [ -f "$ORIG_BOOT" ]; then
    python3 "$ROOT/scripts/repack_boot.py" \
        "$ORIG_BOOT" "$OUT/arch/arm64/boot/Image" "$ROOT/boot_new.img"
    echo ""
    echo "=== 完成 ==="
    ls -lh "$ROOT/boot_new.img"
    sha256sum "$ROOT/boot_new.img"
    echo "boot_new.img 为修补内核的 boot 镜像(未 root),可用 fastboot boot 临时启动验证。"
else
    echo "警告: 缺少原版 boot ($ORIG_BOOT),跳过打包。Image 仍可用于 AK3/magiskboot 方式。"
fi
exit 0
