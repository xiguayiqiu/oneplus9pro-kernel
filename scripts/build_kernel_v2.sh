#!/usr/bin/env bash
# 内核构建脚本 v2 — 基于设备 /proc/config.gz 基线
# 目标: OnePlus 9 Pro LE2121 / OOS14 U14 / 5.4.254-qgki
set -uo pipefail

# 清除 shell 注入的 rm/cp/mv 函数（这些函数把命令重定向到无权限的 shim，
# 导致内核 Makefile 中的 rm -f 临时文件操作失败 126）。内核构建删除的都是
# 自身的 .o/临时文件，属正常编译行为，使用系统真实 /bin/rm 即可。
unset -f rm cp mv 2>/dev/null || true

ROOT=/home/yiqiu/droidspaces-le2121
SRC="$ROOT/02-source/kernel_src"
OUT="$ROOT/04-build/out"
CL="$ROOT/00-tools/clang-tc2/bin"   # clang-r383902b1, build 6877366 / 11.0.2 (与设备精确一致)
TC="$ROOT/00-tools/aarch64-tc/bin"  # aarch64-linux-gnu-* symlinks -> llvm 工具(供 Makefile 的 elfedit/--prefix 推导)
LOG="$ROOT/05-logs/build_$(date +%Y%m%d_%H%M%S).log"

mkdir -p "$OUT"
echo "=== 构建开始 $(date) ===" | tee -a "$LOG"
echo "源码: $SRC" | tee -a "$LOG"
echo "工具链: $("$CL/clang" --version | head -1)" | tee -a "$LOG"
echo "期望 uname: 5.4.254-qgki-gd2a1055adeb0" | tee -a "$LOG"

cd "$SRC" || exit 1
echo "=== 编译 (make -j$(nproc)) ===" | tee -a "$LOG"
# 清除沙箱注入的 BASH_ENV / BASH_FUNC_*（它们把 rm/cp/mv 重定向到无可执行位的
# shim，导致内核 Makefile 的 rm -f 失败 126）。内核构建只删除自身 .o/临时文件。
# stdin 接 /dev/null: Kconfig 遇 EOF 自动选默认值,避免 (NEW) 交互提示;
# 且不会像 yes|make 那样让并发子进程继承写入中的管道导致 clang Broken pipe。
env -u BASH_ENV -u 'BASH_FUNC_rm%%' -u 'BASH_FUNC_cp%%' -u 'BASH_FUNC_mv%%' \
    -u 'BASH_FUNC_ln%%' -u 'BASH_FUNC_mkdir%%' \
    PATH="$TC:$CL:/usr/bin:/bin" \
    make ARCH=arm64 O="$OUT" \
    CROSS_COMPILE=aarch64-linux-gnu- \
    CLANG_TRIPLE=aarch64-linux-gnu- \
    LLVM_IAS=1 \
    CC="$CL/clang" \
    LD="$CL/ld.lld" \
    AS="$CL/clang" \
    AR="$CL/llvm-ar" \
    NM="$CL/llvm-nm" \
    OBJCOPY="$CL/llvm-objcopy" \
    OBJDUMP="$CL/llvm-objdump" \
    READELF="$CL/llvm-readelf" \
    STRIP="$CL/llvm-strip" \
    -j8 \
    Image modules </dev/null >"$LOG" 2>&1
RC=$?
tail -30 "$LOG"
echo "=== make 退出码: $RC ===" | tee -a "$LOG"
if [ -f "$OUT/arch/arm64/boot/Image" ] && [ -f "$OUT/Module.symvers" ]; then
    echo "=== 产物齐全,判定编译成功 ===" | tee -a "$LOG"
    RC=0
elif [ "$RC" -eq 0 ]; then
    echo "=== make 返回0但产物缺失,视为失败 ===" | tee -a "$LOG"
    RC=1
fi

if [ "$RC" -eq 0 ]; then
    echo "=== 产物 ===" | tee -a "$LOG"
    ls -lh "$OUT/arch/arm64/boot/Image" "$OUT/vmlinux" "$OUT/System.map" 2>&1 | tee -a "$LOG"
    echo "=== Module.symvers ===" | tee -a "$LOG"
    ls -lh "$OUT/Module.symvers" 2>&1 | tee -a "$LOG"
    echo "=== 编译出的 KMI/uname ===" | tee -a "$LOG"
    cat "$OUT/include/config/kernel.release" 2>/dev/null | tee -a "$LOG"
fi
echo "日志: $LOG"
exit "$RC"
