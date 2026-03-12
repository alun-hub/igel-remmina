#!/bin/bash
# Build Remmina + FreeRDP from source with smartcard support
# Run this on Ubuntu 22.04 (or in a Docker container)
#
# Output: remmina-linux64.tar.gz  (place in igel-remmina/ root)

set -e

REMMINA_VERSION="v1.4.35"
FREERDP_VERSION="3.0.0"
INSTALL_PREFIX="/opt/remmina"
BUILD_DIR="/tmp/remmina-build"
OUTPUT_DIR="/tmp/remmina-root"

# --- Dependencies ---
sudo apt-get update
sudo apt-get install -y \
    git cmake ninja-build pkg-config \
    libssl-dev \
    libgtk-3-dev \
    libglib2.0-dev \
    libssh-dev \
    libsecret-1-dev \
    libgcrypt20-dev \
    libvncserver-dev \
    libsodium-dev \
    libspice-client-gtk-3.0-dev \
    libspice-protocol-dev \
    libwebkit2gtk-4.0-dev \
    libx11-dev libxext-dev libxrandr-dev libxi-dev libxrender-dev \
    libxkbcommon-dev libxkbfile-dev \
    libpcsclite-dev \
    libpulse-dev \
    libcups-dev \
    libusb-1.0-0-dev \
    libavcodec-dev libavutil-dev libswscale-dev \
    libudev-dev \
    gettext

mkdir -p "$BUILD_DIR"

# --- Build FreeRDP first (Remmina needs it as a library) ---
echo "==> Building FreeRDP ${FREERDP_VERSION}..."
cd "$BUILD_DIR"

if [ ! -d FreeRDP ]; then
    git clone --depth 1 --branch ${FREERDP_VERSION} https://github.com/FreeRDP/FreeRDP.git
fi

cd FreeRDP && mkdir -p build && cd build

cmake .. \
    -GNinja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" \
    -DWITH_PCSC=ON \
    -DWITH_X11=ON \
    -DWITH_PULSE=ON \
    -DWITH_CUPS=ON \
    -DWITH_CHANNELS=ON \
    -DWITH_CLIENT_CHANNELS=ON \
    -DWITH_SERVER=OFF \
    -DWITH_SAMPLE=OFF \
    -DBUILD_TESTING=OFF \
    -DWITH_SWSCALE=ON \
    -DWITH_FFMPEG=ON

ninja -j"$(nproc)"
DESTDIR="$OUTPUT_DIR" ninja install

# --- Build Remmina ---
echo "==> Building Remmina ${REMMINA_VERSION}..."
cd "$BUILD_DIR"

if [ ! -d Remmina ]; then
    git clone --depth 1 --branch ${REMMINA_VERSION} https://github.com/FreeRDP/Remmina.git
fi

cd Remmina && mkdir -p build && cd build

cmake .. \
    -GNinja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" \
    -DCMAKE_PREFIX_PATH="${OUTPUT_DIR}${INSTALL_PREFIX}" \
    -DWITH_FREERDP3=ON \
    -DWITH_LIBSSH=ON \
    -DWITH_LIBVNCSERVER=ON \
    -DWITH_SPICE=ON \
    -DWITH_PYTHONLIBS=OFF \
    -DWITH_NEWS=OFF \
    -DWITH_APPINDICATOR=OFF

ninja -j"$(nproc)"
DESTDIR="$OUTPUT_DIR" ninja install

# --- Bundle required shared libs ---
echo "==> Bundling shared libraries..."

BUNDLE_LIBS=(
    libpcsclite.so.1
    libssh.so.4
    libsecret-1.so.0
    libgcrypt.so.20
    libvncserver.so.1
    libvncclient.so.1
    libsodium.so.23
    libavcodec.so.58
    libavutil.so.56
    libswscale.so.5
    libpulse.so.0
    libcups.so.2
    libspice-client-gtk-3.0.so.5
    libspice-client-glib-2.0.so.8
)

LIB_DEST="$OUTPUT_DIR${INSTALL_PREFIX}/lib/bundled"
mkdir -p "$LIB_DEST"

for libname in "${BUNDLE_LIBS[@]}"; do
    libpath=$(ldconfig -p | grep "$libname" | awk '{print $NF}' | head -1)
    if [ -n "$libpath" ]; then
        cp -L "$libpath" "$LIB_DEST/"
        echo "Bundled: $libpath"
    else
        echo "WARNING: $libname not found, skipping"
    fi
done

mkdir -p "$OUTPUT_DIR/etc/ld.so.conf.d"
echo "${INSTALL_PREFIX}/lib/bundled" > "$OUTPUT_DIR/etc/ld.so.conf.d/remmina-bundled.conf"

# --- Create tarball ---
TARBALL="remmina-linux64.tar.gz"
tar -czf "/tmp/${TARBALL}" -C "$OUTPUT_DIR" .

echo ""
echo "Done! Copy the tarball to the recipe directory:"
echo "  cp /tmp/${TARBALL} $(dirname "$0")/remmina-linux64.tar.gz"
