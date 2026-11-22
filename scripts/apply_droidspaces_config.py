#!/usr/bin/env python3
"""
在设备 /proc/config.gz 基线 (.config) 上启用 Droidspaces 所需内核选项。
只改动白名单内的选项，输出改动清单，绝不触碰其它项。

用法: apply_droidspaces_config.py <input.config> <output.config> <change.log>

策略:
 - 必需项 (MUST): 官方 check 的 must-have,打开为 =y
 - 推荐项 (RECOMMENDED): 官方推荐,打开为 =y
 - 禁止项 (FORBIDDEN): CFS_BANDWIDTH / CGROUP_PIDS,强制保持 not set
"""
import sys, re

# 必开项 — Droidspaces must-have (GKI 5.4)
MUST = [
    "CONFIG_SYSVIPC",
    "CONFIG_POSIX_MQUEUE",
    "CONFIG_PID_NS",
    "CONFIG_IPC_NS",
    "CONFIG_DEVTMPFS",
    "CONFIG_NETFILTER_XT_MATCH_ADDRTYPE",
]
# 推荐项 — 网络/沙箱/UFW/fail2ban/NixOS
RECOMMENDED = [
    "CONFIG_USER_NS",
    "CONFIG_IP6_NF_NAT",
    "CONFIG_IP6_NF_TARGET_MASQUERADE",
    "CONFIG_MACVLAN",
    "CONFIG_IP_NF_TARGET_REJECT",
    "CONFIG_IP6_NF_TARGET_REJECT",
    "CONFIG_NETLINK_DIAG",
    "CONFIG_NETFILTER_XT_TARGET_LOG",
    "CONFIG_NETFILTER_XT_MATCH_RECENT",
    "CONFIG_IP_SET",
    "CONFIG_IP_SET_HASH_IP",
    "CONFIG_IP_SET_HASH_NET",
    "CONFIG_NETFILTER_XT_SET",
    "CONFIG_TMPFS_POSIX_ACL",
    "CONFIG_TMPFS_XATTR",
]
# 严禁开启 — 破坏 GKI kABI 且无补丁
FORBIDDEN = [
    "CONFIG_CFS_BANDWIDTH",
    "CONFIG_CGROUP_PIDS",
]


def set_option(lines, name, value="y"):
    """把 name 设为 =value。返回 (new_lines, old_value_str)。"""
    pat_set = re.compile(rf"^({re.escape(name)})=.*$")
    pat_unset = re.compile(rf"^# {re.escape(name)} is not set$")
    out = []
    found = False
    old = "<absent>"
    for ln in lines:
        m = pat_set.match(ln)
        if m:
            found = True
            old = ln.split("=", 1)[1]
            out.append(f"{name}={value}")
            continue
        m = pat_unset.match(ln)
        if m:
            found = True
            old = "not set"
            out.append(f"{name}={value}")
            continue
        out.append(ln)
    if not found:
        out.append(f"{name}={value}")
    return out, old


def main():
    if len(sys.argv) != 4:
        print(__doc__)
        sys.exit(2)
    src, dst, log = sys.argv[1:4]
    with open(src, "r", encoding="utf-8", errors="replace") as f:
        lines = [l.rstrip("\n").rstrip("\r") for l in f]

    changes = []
    for name in MUST + RECOMMENDED:
        lines, old = set_option(lines, name, "y")
        changes.append((("MUST" if name in MUST else "RECOMMENDED"), name, old, "y"))
    # 强制禁止项保持 not set
    for name in FORBIDDEN:
        pat = re.compile(rf"^# {re.escape(name)} is not set$")
        if any(pat.match(l) for l in lines):
            changes.append(("FORBIDDEN", name, "not set", "not set (kept)"))
        elif any(re.match(rf"^{re.escape(name)}=", l) for l in lines):
            # 竟然开着 -> 关闭
            lines, old = set_option(lines, name)
            # set_option 只能设 =y;这里直接改写为 not set
            newlines = []
            for l in lines:
                if re.match(rf"^{re.escape(name)}=", l):
                    newlines.append(f"# {name} is not set")
                else:
                    newlines.append(l)
            lines = newlines
            changes.append(("FORBIDDEN", name, old, "FORCED not set"))
        else:
            lines.append(f"# {name} is not set")
            changes.append(("FORBIDDEN", name, "<absent>", "not set (added)"))

    with open(dst, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    with open(log, "w", encoding="utf-8") as f:
        f.write("category\toption\told\tnew\n")
        for c in changes:
            f.write("\t".join(c) + "\n")
    print(f"已生成 {dst}")
    print(f"改动 {len(changes)} 项,明细见 {log}")
    for c in changes:
        print(f"  {c[0]:12s} {c[1]:42s} {c[2]:10s} -> {c[3]}")


if __name__ == "__main__":
    main()
