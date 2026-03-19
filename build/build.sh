#!/bin/bash
# =============================================================================
# build.sh – Bygger Remmina + FreeRDP 3.x för IGEL OS 12
#
# Förutsättningar:
#   - Podman (eller Docker) installerat och igång
#   - Nätverksåtkomst för att klona FreeRDP och Remmina
#
# Resultat:
#   - remmina.tar.bz2 i denna katalog, redo att användas med igelpkg build
#
# Användning:
#   ./build.sh [igel_os_version]
#   Exempel: ./build.sh 12.7.4   (default: 12.7.4)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OS12_CLEAN="${1:-12.7.4}"
IMAGE_NAME="remmina-igel-builder"
OUTPUT_TAR="${PROJECT_DIR}/remmina.tar.bz2"

# Använd podman om tillgängligt, annars docker
CONTAINER_CMD="$(command -v podman 2>/dev/null || command -v docker)"
echo "Använder: ${CONTAINER_CMD}"

echo "=================================================="
echo " Bygger Remmina för IGEL OS ${OS12_CLEAN}"
echo "=================================================="

# --- Steg 1: Bygg container-imagen ---
echo ""
echo "[1/4] Bygger container-image..."
${CONTAINER_CMD} build -t "${IMAGE_NAME}" "${SCRIPT_DIR}"

# --- Steg 2: Hämta clean-listor från IGEL Community ---
echo ""
echo "[2/4] Hämtar clean-listor för IGEL OS ${OS12_CLEAN}..."
CLEAN_BASE="https://raw.githubusercontent.com/IGEL-Community/IGEL-Custom-Partitions/master/utils/igelos_usr"
wget -q -O "${SCRIPT_DIR}/clean_cp_usr_lib.sh"   "${CLEAN_BASE}/clean_cp_usr_lib.sh" || true
wget -q -O "${SCRIPT_DIR}/clean_cp_usr_share.sh" "${CLEAN_BASE}/clean_cp_usr_share.sh" || true
wget -q -O "${SCRIPT_DIR}/${OS12_CLEAN}_usr_lib.txt"   "${CLEAN_BASE}/${OS12_CLEAN}_usr_lib.txt" || \
  wget -q -O "${SCRIPT_DIR}/${OS12_CLEAN}_usr_lib.txt" "${CLEAN_BASE}/clean/${OS12_CLEAN}_usr_lib.txt" || true
wget -q -O "${SCRIPT_DIR}/${OS12_CLEAN}_usr_share.txt" "${CLEAN_BASE}/${OS12_CLEAN}_usr_share.txt" || \
  wget -q -O "${SCRIPT_DIR}/${OS12_CLEAN}_usr_share.txt" "${CLEAN_BASE}/clean/${OS12_CLEAN}_usr_share.txt" || true
chmod +x "${SCRIPT_DIR}/clean_cp_usr_lib.sh" "${SCRIPT_DIR}/clean_cp_usr_share.sh" 2>/dev/null || true
echo "   Clean-listor nedladdade."

# --- Steg 3: Kör container och extrahera output ---
echo ""
echo "[3/4] Kör build-container och extraherar binärer..."

# Skapa ett temporärt script som körs inuti containern
cat > "${SCRIPT_DIR}/build-tar.sh" <<'INNERSCRIPT'
#!/bin/bash
set -euo pipefail

OUTPUT_DIR="/output"
CLEAN_DIR="/clean"
OS12_CLEAN_VERSION="${OS12_CLEAN_VERSION:-12.7.4}"

echo "  Städar bort filer som redan finns i IGEL OS ${OS12_CLEAN_VERSION}..."
/clean/clean_cp_usr_lib.sh   "/clean/${OS12_CLEAN_VERSION}_usr_lib.txt"   "${OUTPUT_DIR}/usr/lib"
/clean/clean_cp_usr_share.sh "/clean/${OS12_CLEAN_VERSION}_usr_share.txt" "${OUTPUT_DIR}/usr/share"

echo "  Buntar bibliotek som IGEL OS saknar..."
LIB_DIR="${OUTPUT_DIR}/usr/lib/x86_64-linux-gnu"
mkdir -p "${LIB_DIR}"

# Ta bort python-plugin (kräver libpython3.10, inte nödvändig för RDP)
rm -f "${OUTPUT_DIR}/usr/lib/x86_64-linux-gnu/remmina/plugins/remmina-plugin-python_wrapper.so"

# Kopiera lib och alla dess versionssymboliska länkar
copy_lib() {
    local name="$1"
    for f in $(find /usr/lib/x86_64-linux-gnu /usr/lib /lib/x86_64-linux-gnu -maxdepth 1 -name "${name}*" 2>/dev/null); do
        dest="${LIB_DIR}/$(basename "$f")"
        [ ! -f "$dest" ] && cp -L "$f" "${LIB_DIR}/" 2>/dev/null && echo "    $f" || true
    done
}

# SSH
copy_lib "libssh.so"
# Avahi (service discovery)
copy_lib "libavahi-ui-gtk3.so"
copy_lib "libavahi-client.so"
copy_lib "libavahi-common.so"
copy_lib "libavahi-glib.so"
# VNC
copy_lib "libvncclient.so"
# Sodium
copy_lib "libsodium.so"
# FFmpeg och ICU: Bookworm-versioner matchar IGEL OS – behöver inte buntas
# FreeRDP3 (IGEL OS har bara FreeRDP2)
copy_lib "libfreerdp3.so"
copy_lib "libfreerdp-client3.so"
copy_lib "libwinpr3.so"
copy_lib "libwinpr-tools3.so"
copy_lib "libuwac0.so"

echo "  Patchar RPATH i binärer..."
# Remmina binary: leta i usr/lib/x86_64-linux-gnu
find "${OUTPUT_DIR}/usr/bin" -name "remmina" -exec \
    patchelf --set-rpath '$ORIGIN/../lib/x86_64-linux-gnu' {} \;

# Remmina plugins ligger i usr/lib/x86_64-linux-gnu/remmina/plugins/
# De behöver hitta FreeRDP3-libs i ../.. (= usr/lib/x86_64-linux-gnu)
find "${OUTPUT_DIR}/usr/lib" -path "*/remmina/plugins/*.so" -exec \
    patchelf --set-rpath '$ORIGIN/../..' {} \; 2>/dev/null || true

# FreeRDP3 libs: leta i sin egna katalog
find "${OUTPUT_DIR}/usr/lib/x86_64-linux-gnu" -maxdepth 1 -name "libfreerdp*.so*" -o \
     -name "libwinpr*.so*" -o -name "libuwac*.so*" | while read f; do
    patchelf --set-rpath '$ORIGIN' "$f" 2>/dev/null || true
done

echo "  Packar remmina.tar.bz2..."
cd "${OUTPUT_DIR}"
tar cvjf /out/remmina.tar.bz2 .
echo "  Klart!"
INNERSCRIPT
chmod +x "${SCRIPT_DIR}/build-tar.sh"

# Kör container med volymer
${CONTAINER_CMD} run --rm \
    -e OS12_CLEAN_VERSION="${OS12_CLEAN}" \
    -v "${SCRIPT_DIR}:/clean:ro,z" \
    -v "${SCRIPT_DIR}:/out:z" \
    "${IMAGE_NAME}" \
    /bin/bash /clean/build-tar.sh

# --- Steg 4: Placera tar.bz2 rätt ---
echo ""
echo "[4/4] Kopierar remmina.tar.bz2 till projektrot..."
if [ -f "${SCRIPT_DIR}/remmina.tar.bz2" ]; then
    mv "${SCRIPT_DIR}/remmina.tar.bz2" "${OUTPUT_TAR}"
fi

echo ""
echo "=================================================="
echo " KLART: ${OUTPUT_TAR}"
echo ""
echo " Nästa steg:"
echo "   1. Kopiera remmina.tar.bz2 till /tmp/ på build-maskinen:"
echo "      cp ${OUTPUT_TAR} /tmp/remmina.tar.bz2"
echo ""
echo "   2. Kör igelpkg build inifrån IGEL SDK-containern:"
echo "      podman run --rm \\"
echo "        -v /tmp/remmina.tar.bz2:/tmp/remmina.tar.bz2 \\"
echo "        -v ${PROJECT_DIR}:/app \\"
echo "        igelpkg:latest \\"
echo "        bash -c 'cd /app && igelpkg build -a x64 -sp'"
echo ""
echo "      Resultat: igelpkg.output/remmina-*.ipkg"
echo ""
echo "      Felsökning (behåller temp-filer + logg):"
echo "        igelpkg build -a x64 -sp -kl"
echo "=================================================="
