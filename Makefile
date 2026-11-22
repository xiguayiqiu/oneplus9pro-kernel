# OnePlus 9 Pro (LE2121) Droidspaces 内核仓库
# 用法:
#   make / make all   编译内核并打包出 boot_new.img (等同 ./build.sh)
#   make help         显示本帮助
#   make image        仅编译内核 Image / modules,不打包
#   make kabi         校验 kABI/CRC 兼容
#   make clean        清理编译产物(保留源码与工具链)

.PHONY: all help image kabi clean

help:
	@echo "OnePlus 9 Pro (LE2121) Droidspaces 内核仓库 - 可用目标:"
	@echo "  make / make all   编译内核并打包出 boot_new.img (等同 ./build.sh)"
	@echo "  make help         显示本帮助"
	@echo "  make image        仅编译内核 Image / modules,不打包"
	@echo "  make kabi         校验 kABI/CRC 兼容"
	@echo "  make clean        清理编译产物(保留源码与工具链)"
	@echo ""
	@echo "build.sh 参数: --help | clean | (无参数=编译并打包)"

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

clean:
	rm -rf $(OUT) $(ROOT)/boot_new.img $(ROOT)/build.log
	@echo "已清理编译产物"
