#!/bin/bash
set -euo pipefail

USER_NAME="${1:-tana}"
TARGET="${PISIM_TARGET:-wsl}"
HERE="$(cd "$(dirname "$0")" && pwd)"
export DEBIAN_FRONTEND=noninteractive

say() { printf '\n==> %s\n' "$*"; }

if [ "$(id -u)" != 0 ]; then
	echo "root で動かしてください(wsl -d kazokuai-pi -u root -- bash setup.sh)" >&2
	exit 1
fi

say "電話機のネットワークの設定を先に置きます"
install -d /etc/systemd/system/NetworkManager.service.d /etc/systemd/system/wpa_supplicant.service.d /etc/NetworkManager/conf.d
install -m 0644 "$HERE/files/netns-dropin.conf" /etc/systemd/system/NetworkManager.service.d/kazokuai.conf
install -m 0644 "$HERE/files/netns-dropin.conf" /etc/systemd/system/wpa_supplicant.service.d/kazokuai.conf
install -m 0644 "$HERE/files/NetworkManager-kazokuai.conf" /etc/NetworkManager/conf.d/kazokuai.conf
install -m 0644 "$HERE/files/pisim-net.service" /etc/systemd/system/
install -m 0755 "$HERE/bin/pisim" /usr/local/bin/pisim
systemctl daemon-reload 2>/dev/null || true

say "パッケージを入れます"
rm -f /etc/apt/sources.list.d/raspberrypi.list /usr/share/keyrings/raspberrypi.gpg
dpkg --configure -a
apt-get -f install -y
apt-get update
apt-get install -y --no-install-recommends \
	ca-certificates curl wget gnupg sudo systemd systemd-sysv dbus procps locales tzdata \
	openssh-server unzip git build-essential \
	python3 python3-venv python3-pip python3-numpy python3-tk \
	libportaudio2 alsa-utils libasound2-plugins pulseaudio-utils \
	gpiod iproute2 iputils-ping nftables iw wireless-regdb hostapd dnsmasq-base network-manager wpasupplicant \
	kmod iptables less nano tmux fonts-noto-cjk fonts-dejavu-core \
	flex bison bc libelf-dev libssl-dev dwarves

PI_PKGS="python3-gpiozero python3-lgpio"
if ! apt-get install -y --no-install-recommends $PI_PKGS 2>/dev/null; then
	say "Raspberry Pi のリポジトリから gpiozero と lgpio を入れます"
	. /etc/os-release
	POOL=https://archive.raspberrypi.com/debian/pool/main/r/raspberrypi-archive-keyring/
	KEYDEB=$(curl -fsSL "$POOL" | grep -o 'raspberrypi-archive-keyring_[^"<>]*_all\.deb' | sort -uV | tail -1)
	if [ -z "$KEYDEB" ]; then
		echo "Raspberry Pi の鍵のパッケージが見つかりませんでした: $POOL" >&2
		exit 1
	fi
	TMPK=$(mktemp -d)
	curl -fsSLo "$TMPK/k.deb" "$POOL$KEYDEB"
	dpkg-deb -x "$TMPK/k.deb" "$TMPK/x"
	install -m 0644 "$TMPK/x/usr/share/keyrings/raspberrypi-archive-keyring.pgp" /usr/share/keyrings/raspberrypi.pgp
	rm -rf "$TMPK"
	echo "deb [signed-by=/usr/share/keyrings/raspberrypi.pgp] https://archive.raspberrypi.com/debian ${VERSION_CODENAME} main" >/etc/apt/sources.list.d/raspberrypi.list
	cat >/etc/apt/preferences.d/raspberrypi <<-EOF
	Package: *
	Pin: origin archive.raspberrypi.com
	Pin-Priority: 1

	Package: python3-gpiozero python3-colorzero python3-lgpio liblgpio1 lgpio python3-rpi-lgpio
	Pin: origin archive.raspberrypi.com
	Pin-Priority: 500
	EOF
	apt-get update
	apt-get install -y --no-install-recommends $PI_PKGS
fi

say "実機向け(arm64)のプログラムを動かす用意をします"
dpkg --add-architecture arm64
apt-get update
apt-get install -y --no-install-recommends libc6:arm64 libasound2t64:arm64 libpulse0:arm64
if [ -x "$HERE/bin/qemu-aarch64-gpio" ]; then
	install -D -m 0755 "$HERE/bin/qemu-aarch64-gpio" /usr/local/libexec/pisim/qemu-aarch64-gpio
else
	bash "$HERE/build-qemu-gpio.sh" /usr/local/libexec/pisim
fi
install -m 0755 "$HERE/files/pisim-arm64" /usr/local/libexec/pisim/pisim-arm64
install -m 0644 "$HERE/files/pisim-arm64.service" /etc/systemd/system/
if [ -f "$HERE/kazokuai-device" ]; then
	install -m 0755 "$HERE/kazokuai-device" /usr/local/bin/kazokuai-device
fi
sed "s/--user tana/--user ${USER_NAME}/" "$HERE/files/kazokuai-device.service" >/etc/systemd/system/kazokuai-device.service
install -d -m 0750 /etc/kazokuai/secret

say "日本語の表示と日本の時刻にします"
sed -i -E 's/^# *(ja_JP\.UTF-8 UTF-8)/\1/' /etc/locale.gen
locale-gen
update-locale LANG=ja_JP.UTF-8
echo 'LANG=ja_JP.UTF-8' >/etc/locale.conf
ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
echo Asia/Tokyo >/etc/timezone

say "電話機のラズパイ(pisim)を入れます"
install -m 0755 "$HERE/bin/pisim" /usr/local/bin/pisim
install -m 4755 "$HERE/bin/pisim" /usr/local/bin/pisim-shell
grep -qx /usr/local/bin/pisim-shell /etc/shells || echo /usr/local/bin/pisim-shell >>/etc/shells
install -d /usr/local/share/kazokuai-pisim
install -m 0644 "$HERE/gui/kazokuai-phone.py" /usr/local/share/kazokuai-pisim/
install -m 0755 "$HERE/files/kazokuai-phone" /usr/local/bin/kazokuai-phone
install -m 0644 "$HERE/files/kazokuai-phone.desktop" /usr/share/applications/
[ -f /etc/kazokuai-pisim.conf ] || install -m 0644 "$HERE/files/kazokuai-pisim.conf" /etc/
install -m 0644 "$HERE/files/asound.conf" /etc/asound.conf
install -m 0644 "$HERE/files/pisim.service" /etc/systemd/system/
install -d /etc/kazokuai
[ -f /etc/kazokuai/device.env ] || install -m 0644 "$HERE/files/device.env" /etc/kazokuai/
install -d /etc/ssh/sshd_config.d
install -m 0644 "$HERE/files/sshd_kazokuai.conf" /etc/ssh/sshd_config.d/kazokuai.conf
grep -q '^PULSE_SERVER=' /etc/environment 2>/dev/null || echo 'PULSE_SERVER=unix:/mnt/wslg/PulseServer' >>/etc/environment
install -m 0644 "$HERE/files/profile-kazokuai.sh" /etc/profile.d/kazokuai.sh
install -m 0644 "$HERE/files/pisim-wifi-module.service" /etc/systemd/system/
install -m 0755 "$HERE/build-wifi-module.sh" /usr/local/share/kazokuai-pisim/

if [ "$TARGET" = wsl ]; then
	say "電話機の無線(wlan0)のモジュールを用意します(初回は 10 分ほどかかります)"
	bash "$HERE/build-wifi-module.sh" || echo "無線のモジュールを作れませんでした。wlan0 なしで続けます(有線の eth0 は使えます)。"
fi

say "ユーザー ${USER_NAME} を用意します"
for g in gpio i2c spi; do
	getent group "$g" >/dev/null || groupadd --system "$g"
done
PI_GROUPS=""
for g in adm dialout cdrom sudo audio video plugdev games users input render netdev spi i2c gpio; do
	getent group "$g" >/dev/null && PI_GROUPS="${PI_GROUPS:+$PI_GROUPS,}$g"
done

if ! id "$USER_NAME" >/dev/null 2>&1; then
	useradd -m -s /usr/local/bin/pisim-shell -G "$PI_GROUPS" "$USER_NAME"
	if [ "$TARGET" = docker ]; then
		echo "${USER_NAME} ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/kazokuai
		chmod 0440 /etc/sudoers.d/kazokuai
	else
		echo "${USER_NAME} のパスワードを決めてください(sudo と scp で使います)"
		until passwd "$USER_NAME"; do :; done
	fi
else
	usermod -s /usr/local/bin/pisim-shell -aG "$PI_GROUPS" "$USER_NAME"
fi
install -d -o "$USER_NAME" -g "$USER_NAME" /var/lib/kazokuai

if [ "$TARGET" = docker ]; then
	say "Docker の電話機の設定を書きます"
	echo kazokuai >/etc/hostname
	install -m 0644 "$HERE/files/kazokuai-phone.service" /etc/systemd/system/
	systemctl enable pisim-wifi-module.service pisim-net.service pisim.service pisim-arm64.service \
		kazokuai-device.service kazokuai-phone.service NetworkManager.service
	systemctl disable ssh.service >/dev/null 2>&1 || true
	systemctl mask getty@tty1.service console-getty.service systemd-udevd.service systemd-udevd-control.socket \
		systemd-udevd-kernel.socket systemd-timesyncd.service hostapd.service >/dev/null 2>&1 || true
	systemctl disable dnsmasq.service >/dev/null 2>&1 || true
	echo "==> 用意できました"
	exit 0
fi

say "WSL の設定を書きます(systemd、既定のユーザー、ホスト名 kazokuai)"
cat >/etc/wsl.conf <<EOF
[boot]
systemd=true

[user]
default=${USER_NAME}

[network]
hostname=kazokuai
generateHosts=true
EOF

[ -f /etc/kazokuai/secret/.env ] || install -m 0600 /dev/null /etc/kazokuai/secret/.env
systemctl enable pisim-wifi-module.service pisim-net.service pisim.service pisim-arm64.service \
	kazokuai-device.service ssh.service >/dev/null 2>&1 || true
systemctl disable --now hostapd.service dnsmasq.service >/dev/null 2>&1 || true
systemctl mask hostapd.service >/dev/null 2>&1 || true

cat <<EOF

==> 用意できました。WSL を一度止めると、次から電話機として起動します。
    wsl --terminate kazokuai-pi
EOF
