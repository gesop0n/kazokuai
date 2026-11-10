FROM debian:trixie AS qemu
COPY build-qemu-gpio.sh /build-qemu-gpio.sh
RUN bash /build-qemu-gpio.sh /out

FROM debian:trixie
ENV DEBIAN_FRONTEND=noninteractive
COPY . /opt/kazokuai-pi-sim
COPY --from=qemu /out/qemu-aarch64-gpio /opt/kazokuai-pi-sim/bin/qemu-aarch64-gpio
RUN PISIM_TARGET=docker bash /opt/kazokuai-pi-sim/setup.sh tana \
	&& apt-get clean && rm -rf /var/lib/apt/lists/*

ENV LANG=ja_JP.UTF-8 TZ=Asia/Tokyo
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
