FROM golang:1.20-alpine AS builder

WORKDIR /build
COPY ./matrix-wechat-agent .

RUN apk add --no-cache git ca-certificates
RUN set -ex \
 &&	GOOS=windows GOARCH=386 go build -o matrix-wechat-agent.exe main.go \
 &&	wget -q "https://github.com/ljc545w/ComWeChatRobot/releases/download/3.7.0.30-0.1.1-pre/3.7.0.30-0.1.1-pre.zip" -O CowWeChatRobot.zip \
 &&	unzip -q CowWeChatRobot.zip \
 &&	git clone https://github.com/tom-snow/docker-ComWechat.git dc \
 &&	wget -q "https://github.com/tom-snow/docker-ComWechat/releases/download/v0.2_wc3.7.0.30/Tencent.zip" -O dc/wine/Tencent.zip \
 &&	echo 'build done'

FROM debian:bookworm-slim

ARG DEBIAN_FRONTEND="noninteractive"
ARG TARGETPLATFORM

# To suppress the Wine debug messages
ENV WINEDEBUG=-all

# To suppress Box86's info banner to avoid winetricks to crash
ENV BOX86_NOBANNER=1

# Install additional tools
RUN apt-get update \
 && apt-get install --yes --no-install-recommends wget curl ca-certificates gnupg dumb-init sudo unzip python3

# `cabextract` is needed by winetricks to install most libraries
# `xvfb` is needed in wine to spawn display window because some Windows program can't run without it (using `xvfb-run`)
# If you are sure you don't need it, feel free to remove
RUN apt install --yes cabextract xvfb

# Install box86 and box64
COPY install-box.sh /
RUN bash /install-box.sh \
 && rm /install-box.sh

# Install wine, wine64, and winetricks
COPY install-wine.sh /
RUN bash /install-wine.sh \
 && rm /install-wine.sh

# Install box wrapper for wine
COPY wrap-wine.sh /
RUN bash /wrap-wine.sh \
 && rm /wrap-wine.sh

# Clean up
RUN apt-get -y autoremove \
 && apt-get clean autoclean \
 && rm -rf /tmp/* /var/tmp/* /var/lib/apt/lists

# Add user and group
RUN groupadd group \
  && useradd -m -g group user \
  && usermod -a -G audio user \
  && usermod -a -G video user \
  && chsh -s /bin/bash user \
  && echo 'User Created'

# Initialise wine
RUN mv /root/wine /home/user/ \
  && chown -R user:group /home/user/ \
  && su user -c 'wine wineboot' \
  \
  # wintricks
  && su user -c 'winetricks -q msls31' \
  && su user -c 'winetricks -q ole32' \
  && su user -c 'winetricks -q riched20' \
  && su user -c 'winetricks -q riched30' \
  # && su user -c 'winetricks -q win7' \
  \
  # Clean
  && rm -fr /home/user/{.cache,tmp}/* \
  && rm -fr /tmp/* \
  && echo 'Wine Initialized'

RUN echo 'user ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
USER user

WORKDIR /home/user

COPY --from=builder /build/dc/wine/simsun.ttc  /home/user/.wine/drive_c/windows/Fonts/simsun.ttc
COPY --from=builder /build/dc/wine/微信.lnk /home/user/.wine/drive_c/users/Public/Desktop/微信.lnk
COPY --from=builder /build/dc/wine/system.reg  /home/user/.wine/system.reg
COPY --from=builder /build/dc/wine/user.reg  /home/user/.wine/user.reg
COPY --from=builder /build/dc/wine/userdef.reg /home/user/.wine/userdef.reg

COPY --from=builder /build/dc/wine/Tencent.zip /Tencent.zip
COPY --from=builder /build/matrix-wechat-agent.exe /home/user/matrix-wechat-agent/matrix-wechat-agent.exe
COPY --from=builder /build/http/SWeChatRobot.dll /home/user/matrix-wechat-agent/SWeChatRobot.dll
COPY --from=builder /build/http/wxDriver.dll /home/user/matrix-wechat-agent/wxDriver.dll
COPY ./run.py /usr/bin/run.py

RUN set -ex \
 &&	sudo chmod a+x /usr/bin/run.py \
 &&	unzip -q /Tencent.zip \
 &&	cp -rf wine/Tencent "/home/user/.wine/drive_c/Program Files/" \
 &&	rm -rf Tencent.zip \
 &&	echo 'build done'

 # Disable upgrade Wechat
COPY disable-upgrade.sh /
RUN bash /disable-upgrade.sh \
 && sudo rm /disable-upgrade.sh
COPY patch-hosts.sh /
RUN bash /patch-hosts.sh \
 && sudo rm /patch-hosts.sh

WORKDIR /home/user/matrix-wechat-agent

ENTRYPOINT ["/usr/bin/dumb-init"]
CMD ["/usr/bin/run.py"]
