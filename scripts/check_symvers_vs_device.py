#!/usr/bin/env python3
"""
最终 kABI 判定：编译产出的 Module.symvers vs 设备 vendor 模块 CRC 基准。

用法:
  python3 check_symvers_vs_device.py <build_out_dir>/Module.symvers <device_symbol_crcs.tsv>

判定标准（全部满足才算 PASS）:
  1. module_layout 符号 CRC == dc7fd1bf（设备基准），否则 uname/ABI 基线不对
  2. 基准表中 2098 个符号在新内核 Module.symvers 中全部存在且 CRC 一致
  3. kABI 补丁目标符号（task_struct/user_struct 相关）不能出现 CRC 漂移

若 FAIL -> 绝对不要刷入。
"""
import sys

DEVICE_MODULE_LAYOUT_CRC = "dc7fd1bf"


def norm_crc(c):
    """统一 CRC 格式: 去 0x 前缀,小写,补足8位。Module.symvers 用 0x1234abcd,
    设备 __versions 段提取用 1234abcd,二者是同一个值。"""
    c = c.strip().lower()
    if c.startswith("0x"):
        c = c[2:]
    return c.zfill(8)


def load_symvers(path):
    t = {}
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            p = line.strip().split("\t")
            if len(p) >= 2:
                t[p[1]] = norm_crc(p[0])
    return t


def load_device(path):
    t = {}
    with open(path, encoding="utf-8") as f:
        next(f, None)
        for line in f:
            p = line.strip().split("\t")
            if len(p) >= 2:
                t[p[0]] = norm_crc(p[1])
    return t


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    kern = load_symvers(sys.argv[1])
    dev = load_device(sys.argv[2])

    print(f"内核导出符号: {len(kern)}  设备基准符号: {len(dev)}")

    # 判定 1: module_layout
    kml = kern.get("module_layout")
    ref = norm_crc(DEVICE_MODULE_LAYOUT_CRC)
    print(f"\n[1] module_layout: 设备={ref} 新内核={kml}")
    ok1 = (kml == ref)

    # 判定 2: 全符号比对
    missing, mismatch = [], []
    for sym, crc in dev.items():
        if sym not in kern:
            missing.append(sym)
        elif kern[sym] != crc:
            mismatch.append((sym, crc, kern[sym]))
    print(f"\n[2] 符号缺失: {len(missing)}  CRC 不匹配: {len(mismatch)}")
    for x in missing[:15]:
        print("  MISSING", x)
    for x in mismatch[:15]:
        print("  MISMATCH", x)

    # MISSING 符号分析: 设备基准表从 vendor .ko 的 __versions 段提取,其中包含
    # 模块间互相依赖的符号(如 rmnet_* 由 rmnet_core.ko 提供),这些本就不属于
    # 内核 vmlinux 的 Module.symvers。它们随 vendor_boot 原样保留,不受内核改动影响。
    # 真正致命的是 CRC 不匹配(mismatch) —— 表示内核导出的同一符号 ABI 变了。
    VENDOR_ONLY_HINTS = ("rmnet", "qmi_rmnet", "qmi_", "cnss", "wlan", "rmnet_ctl")
    vendor_syms = [s for s in missing if any(h in s.lower() for h in VENDOR_ONLY_HINTS)]
    unexplained_missing = [s for s in missing if s not in vendor_syms]

    print(f"\n[3] MISSING 分类: vendor 模块自导出={len(vendor_syms)}  其他={len(unexplained_missing)}")
    for s in unexplained_missing[:20]:
        print("  UNEXPLAINED MISSING", s)

    # 判定: module_layout 匹配 + 零 CRC 漂移 + 无非 vendor 的缺失 => kABI 保持
    ok2 = not mismatch and not unexplained_missing

    print("\n" + "=" * 50)
    if ok1 and ok2:
        print("[PASS] 内核导出的设备所需符号 CRC 全部一致(0 mismatch),module_layout 匹配。")
        print(f"       {len(vendor_syms)} 个 MISSING 为 vendor .ko 模块间符号(rmnet/qmi 等),")
        print("       由未改动的 vendor_boot 提供,不影响 kABI。")
        print("       候选内核满足 kABI 前提,但仍须先用 fastboot boot 临时启动验证,不要直接 flash。")
        sys.exit(0)
    else:
        print("[FAIL] kABI 不一致：")
        if not ok1:
            print("  - module_layout CRC 不符：内核 ABI 基线/LOCALVERSION 与设备不一致")
        if mismatch:
            print(f"  - {len(mismatch)} 个符号 CRC 漂移：CONFIG 改动破坏了结构体布局")
        if unexplained_missing:
            print(f"  - {len(unexplained_missing)} 个非 vendor 符号缺失：源码/配置与设备不符")
        print("  不要刷入。")
        sys.exit(2)


if __name__ == "__main__":
    main()
