#!/usr/bin/env python3
"""
kABI 验证工具：比对 vendor 模块期望的符号 CRC 与新内核导出的符号 CRC。
只在 Linux 环境、内核编译完成后使用。

用法:
  python3 verify_kabi.py <Module.symvers> <vendor_modules_dir>

  Module.symvers : 编译产物 out/Module.symvers，每行 "CRC\\tsymbol\\tmodule\\texport_type"
  vendor_modules_dir : 从设备提取的 .ko 目录

原理:
  Linux 模块在 __versions 段中记录它依赖的每个内核符号的 CRC（modversions）。
  若新内核该符号的 CRC 与模块记录的不一致，模块会被拒绝加载 -> bootloop。
  本脚本用 readelf 提取 .ko 的 __versions 段，与 Module.symvers 比对。
"""
import os
import re
import subprocess
import sys


def read_module_symvers(path):
    """解析 Module.symvers -> {symbol: crc}"""
    table = {}
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            parts = line.strip().split("\t")
            if len(parts) >= 2:
                crc, sym = parts[0], parts[1]
                if sym in table and table[sym] != crc:
                    print(f"WARN duplicate symbol {sym}: {table[sym]} vs {crc}")
                table[sym] = crc
    return table


def module_crcs(ko_path):
    """从 .ko 的 __versions 段提取 {symbol: crc}，需 readelf。"""
    try:
        out = subprocess.check_output(
            ["readelf", "-x", "__versions", ko_path],
            stderr=subprocess.DEVNULL, text=True)
    except Exception:
        return {}
    # hex dump 形如  0x00000000 12345678 00000000 00000010  symname...
    result = {}
    for line in out.splitlines():
        m = re.match(r"\s*0x[0-9a-f]+\s+([0-9a-f]{8})\s+[0-9a-f]{8}\s+[0-9a-f]{8}\s+(\S+)", line)
        if m:
            result[m.group(2)] = m.group(1)
    return result


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    symvers_path, ko_dir = sys.argv[1], sys.argv[2]
    kernel = read_module_symvers(symvers_path)
    print(f"内核导出符号数: {len(kernel)}")

    kos = []
    for root, _, files in os.walk(ko_dir):
        for fn in files:
            if fn.endswith(".ko"):
                kos.append(os.path.join(root, fn))
    print(f"vendor 模块数: {len(kos)}")

    total_refs = 0
    mismatches = []
    missing = []
    for ko in kos:
        refs = module_crcs(ko)
        for sym, crc in refs.items():
            total_refs += 1
            if sym not in kernel:
                missing.append((os.path.basename(ko), sym))
            elif kernel[sym] != crc:
                mismatches.append((os.path.basename(ko), sym, crc, kernel[sym]))

    print(f"\n模块符号引用总数: {total_refs}")
    print(f"符号缺失: {len(missing)}")
    print(f"CRC 不匹配: {len(mismatches)}")
    if missing[:20]:
        print("\n缺失样例 (模块, 符号):")
        for x in missing[:20]:
            print("  ", x)
    if mismatches[:20]:
        print("\nCRC 不匹配样例 (模块, 符号, 模块期望, 内核导出):")
        for x in mismatches[:20]:
            print("  ", x)

    if not missing and not mismatches:
        print("\n[PASS] 所有 vendor 模块的符号 CRC 与新内核一致，kABI 假设成立。")
        sys.exit(0)
    else:
        print("\n[FAIL] kABI 不一致：新内核不可刷入。需调整补丁/配置或换精确源码。")
        sys.exit(2)


if __name__ == "__main__":
    main()
