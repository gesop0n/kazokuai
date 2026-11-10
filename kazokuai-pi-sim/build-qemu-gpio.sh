#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

OUT="${1:-/usr/local/libexec/pisim}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ -x "$OUT/qemu-aarch64-gpio" ]; then
	echo "GPIO 対応の qemu はもう作ってあります: $OUT/qemu-aarch64-gpio"
	exit 0
fi

echo "==> qemu を作る道具とソースを用意します"
SOURCES=/etc/apt/sources.list.d/debian.sources
if [ -f "$SOURCES" ] && ! grep -q '^Types:.*deb-src' "$SOURCES"; then
	sed -i 's/^Types: deb$/Types: deb deb-src/' "$SOURCES"
fi
apt-get update -qq
apt-get install -y -qq --no-install-recommends dpkg-dev ca-certificates build-essential ninja-build meson \
	python3 python3-venv pkg-config libglib2.0-dev libpcre2-dev flex bison >/dev/null
cd "$WORK"
apt-get source -qq qemu >/dev/null
cd qemu-*/

echo "==> GPIO の ioctl を qemu に教えます"
python3 - <<'EOF'
gpio = [
    ("GPIO_GET_CHIPINFO_IOCTL", 0x8044b401, "IOC_R", 68),
    ("GPIO_GET_LINEINFO_UNWATCH_IOCTL", 0xc004b40c, "IOC_RW", 4),
    ("GPIO_V2_GET_LINEINFO_IOCTL", 0xc100b405, "IOC_RW", 256),
    ("GPIO_V2_GET_LINEINFO_WATCH_IOCTL", 0xc100b406, "IOC_RW", 256),
    ("GPIO_V2_GET_LINE_IOCTL", 0xc250b407, "IOC_RW", 592),
    ("GPIO_V2_LINE_SET_CONFIG_IOCTL", 0xc110b40d, "IOC_RW", 272),
    ("GPIO_V2_LINE_GET_VALUES_IOCTL", 0xc010b40e, "IOC_RW", 16),
    ("GPIO_V2_LINE_SET_VALUES_IOCTL", 0xc010b40f, "IOC_RW", 16),
    ("GPIO_GET_LINEINFO_IOCTL", 0xc048b402, "IOC_RW", 72),
    ("GPIO_GET_LINEHANDLE_IOCTL", 0xc16cb403, "IOC_RW", 364),
    ("GPIO_GET_LINEEVENT_IOCTL", 0xc030b404, "IOC_RW", 48),
    ("GPIOHANDLE_GET_LINE_VALUES_IOCTL", 0xc040b408, "IOC_RW", 64),
    ("GPIOHANDLE_SET_LINE_VALUES_IOCTL", 0xc040b409, "IOC_RW", 64),
    ("GPIOHANDLE_SET_CONFIG_IOCTL", 0xc054b40a, "IOC_RW", 84),
    ("GPIO_GET_LINEINFO_WATCH_IOCTL", 0xc048b40b, "IOC_RW", 72),
]

with open("linux-user/syscall_defs.h", "a") as f:
    for name, cmd, _, _ in gpio:
        f.write(f"#define TARGET_{name} 0x{cmd:08x}\n#define PISIM_HOST_{name} 0x{cmd:08x}U\n")

entries = "".join(
    f'  {{ TARGET_{name}, PISIM_HOST_{name}, "{name}", {access}, NULL, '
    f"{{ MK_PTR(MK_ARRAY(TYPE_CHAR, {size})) }} }},\n"
    for name, _, access, size in gpio
)
path = "linux-user/syscall.c"
src = open(path).read()
marker = '#include "ioctls.h"\n'
at = src.index(marker) + len(marker)
open(path, "w").write(src[:at] + entries + src[at:])
EOF

echo "==> qemu-aarch64 を作ります(10 分ほどかかります)"
./configure --target-list=aarch64-linux-user --static --disable-system --disable-tools --disable-docs \
	--disable-werror --disable-capstone --disable-plugins --disable-install-blobs --disable-fdt \
	>"$WORK/configure.log" 2>&1 || { tail -30 "$WORK/configure.log"; exit 1; }
ninja -C build qemu-aarch64 >"$WORK/ninja.log" 2>&1 || { tail -40 "$WORK/ninja.log"; exit 1; }

install -d "$OUT"
install -m 0755 -s build/qemu-aarch64 "$OUT/qemu-aarch64-gpio"
echo "==> できました: $OUT/qemu-aarch64-gpio"
