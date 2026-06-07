#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALLER="${SCRIPT_DIR}/DMInstall.bin"
IMAGE_NAME="liuys36/dameng"
ZIP_FILE=""
IMAGE_TAG=""

detect_version() {
    local zips
    zips=$(ls "${SCRIPT_DIR}"/dm8_*.zip 2>/dev/null)
    [ -z "$zips" ] && { echo "Error: no dm8_*.zip found in ${SCRIPT_DIR}"; exit 1; }

    local count
    count=$(echo "$zips" | wc -l)
    [ "$count" -gt 1 ] && {
        echo "Warning: multiple dm8_*.zip found, using the first one:"
        echo "$zips" | head -1
    }

    local zip
    zip=$(echo "$zips" | head -1)
    ZIP_FILE="$zip"
    IMAGE_TAG=$(basename "$zip" .zip)
}

extract() {
    detect_version

    [ -f "${INSTALLER}" ] && { echo "DMInstall.bin already exists, skip extraction."; return; }

    echo "Extracting DMInstall.bin from ${ZIP_FILE}..."
    local iso
    iso="${SCRIPT_DIR}/$(basename "${ZIP_FILE}" .zip).iso"
    unzip -o "${ZIP_FILE}" -d "${SCRIPT_DIR}" 2>/dev/null
    [ ! -f "$iso" ] && { echo "Error: ISO extraction failed."; exit 1; }

    if   command -v 7z &>/dev/null; then
        7z e "$iso" -o"${SCRIPT_DIR}" DMInstall.bin -y
    elif command -v xorriso &>/dev/null; then
        xorriso -osirrox on -indev "$iso" -extract /DMInstall.bin "${INSTALLER}"
    elif command -v isoinfo &>/dev/null; then
        isoinfo -R -x /DMINSTALL.BIN -i "$iso" > "${INSTALLER}"
    else
        echo "Error: Need 7z, xorriso, or isoinfo to extract ISO."
        echo "Install: brew install p7zip"
        exit 1
    fi
    chmod +x "${INSTALLER}"
    rm -f "$iso"
    echo "Extraction done."
}

build() {
    rm -f "${INSTALLER}"
    extract
    echo "Building ${IMAGE_NAME}:${IMAGE_TAG} ..."
    docker buildx build --platform linux/amd64 --load \
        -t "${IMAGE_NAME}:${IMAGE_TAG}" \
        -f "${SCRIPT_DIR}/Dockerfile" \
        "${SCRIPT_DIR}"
    echo "Build complete: ${IMAGE_NAME}:${IMAGE_TAG}"
}

clean() {
    rm -f "${INSTALLER}"
    echo "Cleaned: DMInstall.bin."
}

case "${1:-build}" in
    build)  build ;;
    clean)  clean ;;
    *)
        echo "Usage: $0 {build|clean}"
        echo ""
        echo "  build  Extract installer and build Docker image (default)"
        echo "  clean  Remove DMInstall.bin"
        exit 1
        ;;
esac
