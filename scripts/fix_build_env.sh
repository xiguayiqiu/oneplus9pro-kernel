#!/usr/bin/env bash
# 修复本机编译环境问题（非内核功能改动，仅让原生 Arch Linux 能构建该 OOS 5.4 内核）
# 1. vendor DTS Makefile 用空格缩进 -> TAB
# 2. scripts/extract-cert.c 移除 OpenSSL 3+/4 已删除的 ENGINE API 调用
#    设备 CONFIG_MODULE_SIG 未启用，pkcs11 分支不会被使用。
set -uo pipefail
SRC=/home/yiqiu/droidspaces-le2121/02-source/kernel_src

echo "=== 1. 修复 vendor DTS Makefile 缩进 ==="
for f in arch/arm64/boot/dts/vendor/oplus/martini/Makefile \
         arch/arm64/boot/dts/vendor/oplus/lemonadev/Makefile; do
  PF=$(readlink -f "$SRC/$f")
  [ -f "$PF" ] || { echo "跳过(不存在): $f"; continue; }
  python3 - "$PF" <<'PY'
import sys
p=sys.argv[1]
lines=open(p,'rb').read().split(b'\n')
out=[(b'\t'+l[8:] if l.startswith(b'        ') else l) for l in lines]
open(p,'wb').write(b'\n'.join(out))
print("fixed", p)
PY
done

# lemonadev 的 else 分支: 赋值行与续行被拆成两行,新 make 报"配方在第一个目标前"
python3 - <<'PY'
p = "/home/yiqiu/droidspaces-le2121/00-tools/mndtv14/vendor/qcom/proprietary/devicetree/oplus/lemonadev/Makefile"
s = open(p).read()
old = "dtb-$(CONFIG_ARCH_LAHAINA) +=\n\tlemonadep-overlay.dtb"
new = "dtb-$(CONFIG_ARCH_LAHAINA) += lemonadep-overlay.dtb"
if old in s:
    open(p, "w").write(s.replace(old, new))
    print("merged lemonadev dtb line")
PY

echo "=== 2. 修复 extract-cert.c (OpenSSL 4.x) ==="
EF="$SRC/scripts/extract-cert.c"
if grep -q "ENGINE_load_builtin_engines" "$EF"; then
  python3 - "$EF" <<'PY'
import sys,re
p=sys.argv[1]
s=open(p).read()
old='''\t} else if (!strncmp(cert_src, "pkcs11:", 7)) {
\t\tENGINE *e;
\t\tstruct {
\t\t\tconst char *cert_id;
\t\t\tX509 *cert;
\t\t} parms;

\t\tparms.cert_id = cert_src;
\t\tparms.cert = NULL;

\t\tENGINE_load_builtin_engines();
\t\tdrain_openssl_errors();
\t\te = ENGINE_by_id("pkcs11");
\t\tERR(!e, "Load PKCS#11 ENGINE");
\t\tif (ENGINE_init(e))
\t\t\tdrain_openssl_errors();
\t\telse
\t\t\tERR(1, "ENGINE_init");
\t\tif (key_pass)
\t\t\tERR(!ENGINE_ctrl_cmd_string(e, "PIN", key_pass, 0), "Set PKCS#11 PIN");
\t\tENGINE_ctrl_cmd(e, "LOAD_CERT_CTRL", 0, &parms, NULL, 1);
\t\tERR(!parms.cert, "Get X.509 from PKCS#11");
\t\twrite_cert(parms.cert);
\t} else {'''
new='''\t} else if (!strncmp(cert_src, "pkcs11:", 7)) {
\t\t/* OpenSSL 3+/4 removed the ENGINE API. This build has
\t\t * CONFIG_MODULE_SIG disabled and does not use PKCS#11 keys. */
\t\tERR(1, "PKCS#11 ENGINE support is unavailable with this OpenSSL");
\t} else {'''
if old in s:
    open(p,'w').write(s.replace(old,new))
    print("patched", p)
else:
    print("pattern not found, may already be patched")
PY
else
  echo "extract-cert.c 已修复"
fi
echo "=== 完成 ==="

echo "=== 3. 修复所有 sh 脚本可执行位(gen_vdso_offsets.sh 等) ==="
cd "$SRC"
find . -path ./.git -prune -o -name "*.sh" -type f -print 2>/dev/null | while read f; do chmod +x "$f" 2>/dev/null; done
chmod +x arch/arm64/kernel/vdso/gen_vdso_offsets.sh 2>/dev/null
echo "完成"

echo "=== 4. usr/include Makefile: 移除 touch(沙箱禁止 utime) ==="
python3 - <<'PY'
p = "$SRC/usr/include/Makefile"
s = open(p).read()
s2 = s.replace("\t\ttouch $@", "\t\t: @  # touch removed: sandbox blocks utime")
if s2 != s:
    open(p, "w").write(s2)
    print("patched", p)
else:
    print("already patched")
PY
echo "全部环境修复完成"

echo "=== 5. arch/Kconfig: RELR 默认 n(匹配设备,避免 ABS32 链接错误) ==="
python3 - <<'PY'
p = "$SRC/arch/Kconfig"
s = open(p).read()
if "\tdefault y\n\thelp\n\t  Store the kernel's dynamic relocations in the RELR" in s:
    s = s.replace("\tdefault y\n\thelp\n\t  Store the kernel's dynamic relocations in the RELR",
                  "\tdefault n  # match device: LLD 11.0.2 does not use RELR\n\thelp\n\t  Store the kernel's dynamic relocations in the RELR", 1)
    open(p, "w").write(s)
print("done")
PY

echo "=== 6. 修复所有 .pl 脚本可执行位(generate_initcall_order.pl 等) ==="
cd "$SRC"
find . -path ./.git -prune -o -name "*.pl" -type f -print 2>/dev/null | while read f; do chmod +x "$f" 2>/dev/null; done
echo "done"
