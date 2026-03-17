#!/bin/bash
# =============================================================================
# build.sh - Builds Remmina + FreeRDP 3.x for IGEL OS 12
#
# Prerequisites:
#   - Podman (or Docker) installed and running
#   - Network access to clone FreeRDP and Remmina
#
# Output:
#   - remmina.tar.bz2 in the project root, ready for igelpkg build
#
# Usage:
#   ./build.sh [igel_os_version]
#   Example: ./build.sh 12.7.4   (default: 12.7.4)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OS12_CLEAN="${1:-12.7.4}"
IMAGE_NAME="remmina-igel-builder"
OUTPUT_TAR="${PROJECT_DIR}/remmina.tar.bz2"

# Use podman if available, otherwise docker
CONTAINER_CMD="$(command -v podman 2>/dev/null || command -v docker)"
echo "Using: ${CONTAINER_CMD}"

echo "=================================================="
echo " Building Remmina for IGEL OS ${OS12_CLEAN}"
echo "=================================================="

# --- Step 1: Build container image ---
echo ""
echo "[1/4] Building container image..."
${CONTAINER_CMD} build -t "${IMAGE_NAME}" "${SCRIPT_DIR}"

# --- Step 2: Download IGEL OS clean lists ---
echo ""
echo "[2/4] Downloading clean lists for IGEL OS ${OS12_CLEAN}..."
CLEAN_BASE="https://raw.githubusercontent.com/IGEL-Community/IGEL-Custom-Partitions/master/utils/igelos_usr"
wget -q -O "${SCRIPT_DIR}/clean_cp_usr_lib.sh"   "${CLEAN_BASE}/clean_cp_usr_lib.sh"
wget -q -O "${SCRIPT_DIR}/clean_cp_usr_share.sh" "${CLEAN_BASE}/clean_cp_usr_share.sh"
wget -q -O "${SCRIPT_DIR}/${OS12_CLEAN}_usr_lib.txt"   "${CLEAN_BASE}/${OS12_CLEAN}_usr_lib.txt"
wget -q -O "${SCRIPT_DIR}/${OS12_CLEAN}_usr_share.txt" "${CLEAN_BASE}/${OS12_CLEAN}_usr_share.txt"
chmod +x "${SCRIPT_DIR}/clean_cp_usr_lib.sh" "${SCRIPT_DIR}/clean_cp_usr_share.sh"
echo "   Clean lists downloaded."

# --- Step 3: Run container and extract output ---
echo ""
echo "[3/4] Running build container and extracting binaries..."

# Create the inner script that runs inside the container
cat > "${SCRIPT_DIR}/build-tar.sh" <<'INNERSCRIPT'
#!/bin/bash
set -euo pipefail

OUTPUT_DIR="/output"
CLEAN_DIR="/clean"
OS12_CLEAN_VERSION="${OS12_CLEAN_VERSION:-12.7.4}"

echo "  Stripping files already present in IGEL OS ${OS12_CLEAN_VERSION}..."
/clean/clean_cp_usr_lib.sh   "/clean/${OS12_CLEAN_VERSION}_usr_lib.txt"   "${OUTPUT_DIR}/usr/lib"
/clean/clean_cp_usr_share.sh "/clean/${OS12_CLEAN_VERSION}_usr_share.txt" "${OUTPUT_DIR}/usr/share"

echo "  Patching RPATH in binaries..."
find "${OUTPUT_DIR}/usr/bin" -name "remmina" -exec \
    patchelf --set-rpath '$ORIGIN/../lib/x86_64-linux-gnu' {} \;

echo "  Creating remmina.tar.bz2..."
cd "${OUTPUT_DIR}"
tar cvjf /out/remmina.tar.bz2 .
echo "  Done!"
INNERSCRIPT
chmod +x "${SCRIPT_DIR}/build-tar.sh"

# Run container with volume mounts
# Note: :z suffix sets correct SELinux context for Podman on SELinux-enabled hosts
${CONTAINER_CMD} run --rm \
    -e OS12_CLEAN_VERSION="${OS12_CLEAN}" \
    -v "${SCRIPT_DIR}:/clean:ro,z" \
    -v "${SCRIPT_DIR}:/out:z" \
    "${IMAGE_NAME}" \
    /bin/bash /clean/build-tar.sh

# --- Step 4: Move tarball to project root ---
echo ""
echo "[4/4] Moving remmina.tar.bz2 to project root..."
if [ -f "${SCRIPT_DIR}/remmina.tar.bz2" ]; then
    mv "${SCRIPT_DIR}/remmina.tar.bz2" "${OUTPUT_TAR}"
fi

echo ""
echo "=================================================="
echo " DONE: ${OUTPUT_TAR}"
echo ""
echo " Next steps:"
echo "   1. Upload remmina.tar.bz2 to a public URL"
echo "   2. Update igel/thirdparty.json with the URL"
echo "   3. Build the IGEL package:"
echo "      cp ${OUTPUT_TAR} /tmp/remmina.tar.bz2"
echo "      podman run --rm \\"
echo "        -v /tmp/remmina.tar.bz2:/tmp/remmina.tar.bz2:ro,z \\"
echo "        -v ${PROJECT_DIR}:/app:z \\"
echo "        --entrypoint /bin/bash localhost/igelpkg:latest \\"
echo "        -c 'cd /app && igelpkg build -a x64'"
echo "      Output: igelpkg.output/remmina-*.ipkg"
echo "=================================================="
