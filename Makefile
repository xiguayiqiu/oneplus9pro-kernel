# OnePlus 9 Pro (LE2121) Droidspaces 内核仓库
# 用法:
#   make / make all   编译内核并打包出 boot_new.img (等同 ./build.sh)
#   make help         显示本帮助
#   make image        仅编译内核 Image / modules,不打包
#   make kabi         校验 kABI/CRC 兼容
#   make root KEY=... 用 KernelPatch 手动修补 boot_new.img 生成 boot_rooted.img
#   make clean        清理编译产物(保留源码与工具链)

.PHONY: all help image kabi root clean

help:
	@echo "OnePlus 9 Pro (LE2121) Droidspaces 内核仓库 - 可用目标:"
	@echo "  make / make all   编译内核并打包出 boot_new.img (等同 ./build.sh)"
	@echo "  make help         显示本帮助"
	@echo "  make image        仅编译内核 Image / modules,不打包"
	@echo "  make kabi         校验 kABI/CRC 兼容"
	@echo "  make root KEY=... 手动修补 boot_new.img -> boot_rooted.img (绕开 APatch 管理器 bug)"
	@echo "  make clean        清理编译产物(保留源码与工具链)"
	@echo ""
	@echo "默认 make all 会实时显示 make 输出(后台跟随 build.log)，无 Broken pipe。"
	@echo "build.sh 参数: --help | clean | --quiet | (无参数=编译并打包并实时显示)"

ROOT := $(shell pwd)
SRC  := $(ROOT)/src/kernel_src
OUT  := $(ROOT)/out
CL   := $(ROOT)/toolchain/clang/bin
TC   := $(ROOT)/toolchain/aarch64/bin

all:
	./build.sh

image:
	mkdir -p $(OUT)
	cp $(ROOT)/config/build.config $(OUT)/.config
	cd $(SRC) && env -u BASH_ENV \
	  -u 'BASH_FUNC_rm%%' -u 'BASH_FUNC_cp%%' -u 'BASH_FUNC_mv%%' \
	  PATH="$(TC):$(CL):/usr/bin:/bin" \
	  make ARCH=arm64 O=$(OUT) \
	  CROSS_COMPILE=aarch64-linux-gnu- CLANG_TRIPLE=aarch64-linux-gnu- LLVM_IAS=1 \
	  CC="$(CL)/clang" LD="$(CL)/ld.lld" AS="$(CL)/clang" \
	  AR="$(CL)/llvm-ar" NM="$(CL)/llvm-nm" \
	  OBJCOPY="$(CL)/llvm-objcopy" OBJDUMP="$(CL)/llvm-objdump" \
	  READELF="$(CL)/llvm-readelf" STRIP="$(CL)/llvm-strip" \
	  -j8 Image modules </dev/null

kabi:
	python3 $(ROOT)/scripts/check_symvers_vs_device.py \
	  $(OUT)/Module.symvers $(ROOT)/config/device_symbol_crcs.tsv

root:
	@test -n "$(KEY)" || { echo "用法: make root KEY=你的强密码(字母+数字,至少8位)"; exit 1; }
	APATCH_KEY="$(KEY)" $(ROOT)/scripts/patch_boot_apatch.sh

clean:
	rm -rf $(OUT) $(ROOT)/boot_new.img $(ROOT)/build.log
	@echo "已清理编译产物"
