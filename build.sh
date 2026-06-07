#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIP_FILE="${SCRIPT_DIR}/dm8_20260427_x86_rh7_64.zip"
ISO_FILE="${SCRIPT_DIR}/dm8_20260427_x86_rh7_64.iso"
INSTALLER="${SCRIPT_DIR}/DMInstall.bin"
IMAGE_NAME="dm8"
IMAGE_TAG="dm8_20260427_x86_rh7_64"

if [ ! -f "${INSTALLER}" ]; then
    echo "Extracting DMInstall.bin from zip/ISO..."

    [ ! -f "${ZIP_FILE}" ] && { echo "Error: ${ZIP_FILE} not found."; exit 1; }

    echo "-> Extracting ISO from zip..."
    unzip -o "${ZIP_FILE}" -d "${SCRIPT_DIR}" 2>/dev/null

    [ ! -f "${ISO_FILE}" ] && { echo "Error: ISO extraction failed."; exit 1; }

    echo "-> Extracting DMInstall.bin from ISO..."
    if command -v 7z &>/dev/null; then
        7z e "${ISO_FILE}" -o"${SCRIPT_DIR}" DMInstall.bin -y
    elif command -v xorriso &>/dev/null; then
        xorriso -osirrox on -indev "${ISO_FILE}" -extract /DMInstall.bin "${INSTALLER}"
    elif command -v isoinfo &>/dev/null; then
        isoinfo -R -x /DMINSTALL.BIN -i "${ISO_FILE}" > "${INSTALLER}"
    else
        echo "Error: Need 7z, xorriso, or isoinfo to extract ISO."
        echo "Install: brew install p7zip"
        exit 1
    fi

    chmod +x "${INSTALLER}"
    echo "Done."
fi

echo "Building ${IMAGE_NAME}:${IMAGE_TAG} ..."
docker buildx build \
    --platform linux/amd64 \
    --load \
    -t "${IMAGE_NAME}:${IMAGE_TAG}" \
    -f "${SCRIPT_DIR}/Dockerfile" \
    "${SCRIPT_DIR}"

echo ""
echo "===== Build complete: ${IMAGE_NAME}:${IMAGE_TAG} ====="
echo ""
echo "Run container:"
echo "  docker run -d --name dm8 \\"
echo "    -p 5236:5236 \\"
echo "    -e SYSDBA_PWD=YourPwd_123 \\"
echo "    -e SYSAUDITOR_PWD=YourPwd_123 \\"
echo "    ${IMAGE_NAME}:${IMAGE_TAG}"
echo ""
echo "Cleanup DMInstall.bin (optional):"
echo "  rm ${INSTALLER}"
