export LANG="${LANG:-ja_JP.UTF-8}"

if [ -d /mnt/wslg ]; then
	export PULSE_SERVER="${PULSE_SERVER:-unix:/mnt/wslg/PulseServer}"
	export DISPLAY="${DISPLAY:-:0}"
	export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
fi
