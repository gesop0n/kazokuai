#!/bin/bash
set -euo pipefail

KVER="$(uname -r)"
OUT="/usr/local/lib/pisim/modules/$KVER"
SRC="/var/cache/pisim/WSL2-Linux-Kernel-$KVER"
TAG="linux-msft-wsl-${KVER%%-*}"

MODULES=(mac80211_hwsim cfg80211 mac80211 libarc4 ccm cmac)
declare -A CONFIG_OF=(
	[mac80211_hwsim]=MAC80211_HWSIM
	[cfg80211]=CFG80211
	[mac80211]=MAC80211
	[libarc4]=CRYPTO_LIB_ARC4
	[ccm]=CRYPTO_CCM
	[cmac]=CRYPTO_CMAC
)
declare -A DIR_OF=(
	[mac80211_hwsim]=drivers/net/wireless/virtual
	[cfg80211]=net/wireless
	[mac80211]=net/mac80211
	[libarc4]=lib/crypto
	[ccm]=crypto
	[cmac]=crypto
)

KCONFIG="$(zcat /proc/config.gz 2>/dev/null || true)"

available() {
	local m="$1"
	[ -d "/sys/module/$m" ] && return 0
	[ -f "$OUT/$m.ko" ] && return 0
	modinfo "$m" >/dev/null 2>&1 && return 0
	grep -qx "CONFIG_${CONFIG_OF[$m]}=y" <<<"$KCONFIG"
}

missing=()
for m in "${MODULES[@]}"; do
	available "$m" || missing+=("$m")
done
if [ ${#missing[@]} -eq 0 ]; then
	echo "無線のモジュールはそろっています。"
	exit 0
fi
echo "==> 作るモジュール: ${missing[*]}"

echo "==> カーネルのモジュールを作る道具を入れます"
apt-get install -y --no-install-recommends build-essential flex bison bc libelf-dev libssl-dev dwarves kmod git ca-certificates

echo "==> WSL のカーネルのソース($TAG)を取ります(数百 MB)"
if [ ! -f "$SRC/Makefile" ]; then
	rm -rf "$SRC"
	mkdir -p "$(dirname "$SRC")"
	git clone --depth 1 --branch "$TAG" https://github.com/microsoft/WSL2-Linux-Kernel "$SRC"
fi
cd "$SRC"
MAKE=(make LOCALVERSION=)

echo "==> 動いているカーネルの設定で用意します"
zcat /proc/config.gz >.config
scripts/config --module MAC80211_HWSIM
"${MAKE[@]}" olddefconfig >/dev/null
SRC_VER="$("${MAKE[@]}" -s kernelrelease)"
if [ "$SRC_VER" != "$KVER" ]; then
	echo "ソースの版 $SRC_VER が、動いているカーネル $KVER と合いません" >&2
	exit 1
fi
"${MAKE[@]}" -j"$(nproc)" modules_prepare

dirs=()
for m in "${missing[@]}"; do
	d="${DIR_OF[$m]}"
	[[ " ${dirs[*]} " == *" $d "* ]] || dirs+=("$d")
done
for d in "${dirs[@]}"; do
	echo "==> $d のモジュールを作ります"
	"${MAKE[@]}" -j"$(nproc)" M="$d" KBUILD_MODPOST_WARN=1 modules
done

install -d "$OUT"
for m in "${missing[@]}"; do
	ko="$(find "${DIR_OF[$m]}" -name "$m.ko" | head -1)"
	if [ -n "$ko" ]; then
		install -m 0644 "$ko" "$OUT/"
	else
		echo "$m.ko ができませんでした" >&2
	fi
done
echo "==> できました: $(ls "$OUT")"
