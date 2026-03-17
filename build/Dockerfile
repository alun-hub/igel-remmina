FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV FREERDP_VERSION=3.10.3
ENV REMMINA_VERSION=v1.4.38

# --- Build dependencies ---
RUN apt-get update && apt-get install -y \
    build-essential cmake ninja-build pkg-config git wget curl \
    python3 python3-pip \
    # FreeRDP build dependencies
    libssl-dev \
    libx11-dev libxext-dev libxinerama-dev libxcursor-dev \
    libxv-dev libxkbfile-dev libxrandr-dev libxi-dev libxrender-dev \
    libxfixes-dev libxtst-dev \
    libasound2-dev libcups2-dev libpulse-dev \
    libavcodec-dev libavutil-dev libswresample-dev libswscale-dev \
    libusb-1.0-0-dev libudev-dev libfuse3-dev \
    libpcsclite-dev \
    libkrb5-dev libgssapi-krb5-2 \
    libcjson-dev \
    libsdl2-dev libsdl2-ttf-dev \
    # Remmina build dependencies
    libgtk-3-dev libglib2.0-dev \
    libvte-2.91-dev \
    libssh-dev \
    libavahi-ui-gtk3-dev \
    libsecret-1-dev \
    libsodium-dev \
    libgnutls28-dev \
    libvncserver-dev \
    libayatana-appindicator3-dev \
    libjson-glib-dev \
    libcurl4-openssl-dev \
    gettext \
    # Packaging tools
    unzip dpkg-dev \
    && rm -rf /var/lib/apt/lists/*

# --- Build FreeRDP 3.x from source ---
WORKDIR /build
RUN git clone --branch ${FREERDP_VERSION} --depth 1 \
    https://github.com/FreeRDP/FreeRDP.git freerdp

WORKDIR /build/freerdp
RUN cmake -GNinja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_INSTALL_LIBDIR=lib/x86_64-linux-gnu \
    -DWITH_OPENSSL=ON \
    -DWITH_PCSC=ON \
    -DWITH_KRB5=ON \
    -DWITH_GSSAPI=ON \
    -DWITH_ALSA=ON \
    -DWITH_PULSE=ON \
    -DWITH_CUPS=ON \
    -DWITH_FFMPEG=ON \
    -DWITH_DSP_FFMPEG=ON \
    -DWITH_SWRESAMPLE=ON \
    -DWITH_SERVER=OFF \
    -DWITH_SAMPLE=OFF \
    -DWITH_WAYLAND=OFF \
    -DBUILD_TESTING=OFF \
    -B build . \
    && ninja -C build \
    && ninja -C build install

# --- Build Remmina from source ---
WORKDIR /build
RUN git clone --branch ${REMMINA_VERSION} --depth 1 \
    https://gitlab.com/Remmina/Remmina.git remmina

WORKDIR /build/remmina
RUN cmake -GNinja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_INSTALL_LIBDIR=lib/x86_64-linux-gnu \
    -DWITH_FREERDP3=ON \
    -DWITH_LIBSSH=ON \
    -DWITH_LIBVNC=ON \
    -DWITH_AVAHI=ON \
    -DWITH_LIBSECRET=ON \
    -DWITH_VTE=ON \
    -DWITH_APPINDICATOR=OFF \
    -DWITH_WWW=OFF \
    -B build . \
    && ninja -C build \
    && DESTDIR=/output ninja -C build install

# Install FreeRDP libs to /output as well
RUN DESTDIR=/output ninja -C /build/freerdp/build install

# Strip headers, cmake files, pkgconfig and desktop files
RUN rm -rf /output/usr/include \
           /output/usr/lib/x86_64-linux-gnu/cmake \
           /output/usr/lib/x86_64-linux-gnu/pkgconfig \
           /output/usr/share/applications \
           /output/usr/share/doc

CMD ["/bin/bash", "/build-tar.sh"]
