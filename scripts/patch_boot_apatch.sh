#!/usr/bin/env bash
# 用 KernelPatch 0.13.9 手动修补 boot.img（绕开 APatch 管理器 patch_dir 问题）
# 用法:
#   APATCH_KEY='你的强密码' ./scripts/patch_boot_apatch.sh [输入boot.img] [输出boot.img]
#   ./scripts/patch_boot_apatch.sh [输入boot.img] [输出boot.img]   # 交互式输入密钥
# 默认输入: boot_new.img   默认输出: boot_rooted.img
set -uo pipefail
unset -f rm cp mv 2>/dev/null || true

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KP_DIR="$ROOT/tools/kernpatch/0.13.9"
KPTOOLS="$KP_DIR/kptools"
KPIMG="$KP_DIR/kpimg"
BOOT_IN="${1:-$ROOT/boot_new.img}"
BOOT_OUT="${2:-$ROOT/boot_rooted.img}"

fail() { echo "错误: $*" >&2; exit 1; }

if [ -n "${APATCH_KEY:-}" ]; then
    KEY="$APATCH_KEY"
else
    read -rsp "SuperKey（字母+数字，至少 8 位）: " KEY
    echo
fi

[[ "$KEY" =~ ^[A-Za-z0-9]{8,}$ ]] || fail "SuperKey 必须是字母+数字且至少 8 位，且不要用弱密码"
[ -x "$KPTOOLS" ] || fail "缺少 $KPTOOLS"
[ -f "$KPIMG" ] || fail "缺少 $KPIMG"
[ -f "$BOOT_IN" ] || fail "找不到输入镜像 $BOOT_IN"

TMP="$(mktemp -d)"
cleanup() {
    python3 - "$TMP" <<'PY'
import shutil, sys
shutil.rmtree(sys.argv[1], ignore_errors=True)
PY
}
trap cleanup EXIT

cp "$KPTOOLS" "$TMP/kptools"
cp "$KPIMG" "$TMP/kpimg"
chmod +x "$TMP/kptools"
cd "$TMP" || exit 1

echo "=== 解包 boot: $BOOT_IN ==="
./kptools unpacknolog "$BOOT_IN" || fail "unpack 失败"
[ -f kernel ] || fail "unpack 后未生成 kernel"

echo "=== 检查 CONFIG_KALLSYMS ==="
./kptools -i kernel -f | grep -q 'CONFIG_KALLSYMS=y' || fail "内核未开启 CONFIG_KALLSYMS"

echo "=== 修补 kernel ==="
./kptools -p -i kernel -S "$KEY" -k kpimg -o kernel.patched || fail "kptools patch 失败"
python3 -c "import os; os.replace('kernel.patched','kernel')"

echo "=== 重打包 boot ==="
./kptools repack "$BOOT_IN" || fail "repack 失败"
[ -f new-boot.img ] || fail "未生成 new-boot.img"
cp new-boot.img "$BOOT_OUT"

echo ""
echo "=== 完成 ==="
ls -lh "$BOOT_OUT"
sha256sum "$BOOT_OUT"
echo "刷入示例（按当前槽位）: fastboot flash boot_b $BOOT_OUT"
echo "首次开机后用同一 SuperKey 在 APatch 管理器激活 Root。"
