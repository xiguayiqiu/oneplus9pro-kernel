#!/usr/bin/env python3
"""
按目标设备实际 boot 镜像格式重新打包：只替换 kernel，保留 ramdisk/cmdline/头部。
基于实测 boot_b.img 的布局（高通 boot header v3 变体）:
  offset 0:    magic "ANDROID!"
  offset 8:    kernel_size    (u32 LE)
  offset 12:   ramdisk_size   (u32 LE)
  offset 16:   os_version     (u32 LE, 0x18000194)
  offset 20:   header_size    (u32 LE, 1580)
  offset 40:   header_version (u32 LE, 3)
  kernel 起点 = 4096 (page_size), ramdisk 起点 = align4096(kernel起点 + kernel_size)

用法: repack_boot.py <original_boot.img> <new_kernel> <output.img>
打印新旧差异摘要; 保留 ramdisk 与 header 其余字段字节级一致。
"""
import struct, sys, hashlib

PAGE = 4096
KERN_OFF = 4096

def align(n, a=PAGE):
    return (n + a - 1) // a * a

def sha(b):
    return hashlib.sha256(b).hexdigest()

def main():
    orig_path, kern_path, out_path = sys.argv[1:4]
    orig = open(orig_path, "rb").read()
    kern = open(kern_path, "rb").read()

    assert orig[:8] == b"ANDROID!", "非标准 boot magic"
    ksize_old = struct.unpack_from("<I", orig, 8)[0]
    rsize     = struct.unpack_from("<I", orig, 12)[0]
    hdr_size  = struct.unpack_from("<I", orig, 20)[0]
    hdr_ver   = struct.unpack_from("<I", orig, 40)[0]
    ramdisk_off = align(KERN_OFF + ksize_old)
    ramdisk = orig[ramdisk_off:ramdisk_off + rsize]

    print("=== 原镜像 ===")
    print(f"kernel_size={ksize_old} ramdisk_size={rsize} hdr_size={hdr_size} hdr_ver={hdr_ver}")
    print(f"kernel@{KERN_OFF} ramdisk@{ramdisk_off} (0x{ramdisk_off:x})")
    print(f"ramdisk sha256={sha(ramdisk)}")
    print(f"新 kernel: size={len(kern)} sha256={sha(kern)}")

    # 检查 kernel 是否是 ARM64 Image (EFI stub 以 MZ 开头,历史记录)
    print(f"新 kernel 前16字节: {kern[:16].hex()}")

    # 构造新镜像: header(到KERN_OFF) + kernel + pad + ramdisk + pad到原size
    head = bytearray(orig[:KERN_OFF])  # 保留整个 header 区(含页内填充)
    struct.pack_into("<I", head, 8, len(kern))  # 更新 kernel_size

    new_ramdisk_off = align(KERN_OFF + len(kern))
    body = bytearray()
    body += kern
    body += b"\x00" * (new_ramdisk_off - (KERN_OFF + len(kern)))
    body += ramdisk

    out = bytearray(head) + body
    # 保持总大小不变(若新镜像更小则补0;更大则允许增长)
    if len(out) < len(orig):
        out += b"\x00" * (len(orig) - len(out))

    open(out_path, "wb").write(out)
    print("=== 新镜像 ===")
    print(f"总大小: {len(orig)} -> {len(out)}")
    print(f"kernel@{KERN_OFF} size={len(kern)}")
    print(f"ramdisk@{new_ramdisk_off} size={rsize} sha256={sha(bytes(body[new_ramdisk_off-KERN_OFF:new_ramdisk_off-KERN_OFF+rsize]))}")
    print(f"输出: {out_path} sha256={sha(bytes(out))}")

    # 校验: ramdisk 字节级一致, header 除 kernel_size 外一致
    assert bytes(out[new_ramdisk_off:new_ramdisk_off+rsize]) == ramdisk, "ramdisk 不一致!"
    hdr_diff = sum(1 for i in range(KERN_OFF) if orig[i] != out[i])
    print(f"header 区字节差异数: {hdr_diff} (期望=4, 仅 kernel_size 字段)")

if __name__ == "__main__":
    main()
