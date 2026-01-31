#!/usr/bin/env bash
#
# Build STaBioM CLI as a standalone binary using PyInstaller.
#
# Usage:
#   ./scripts/build-release.sh [--version VERSION] [--clean]
#
# Options:
#   --version VERSION   Set version string (default: dev)
#   --clean            Clean build directories before building
#
# Requirements:
#   - Python 3.9+
#   - pip install pyinstaller
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
VERSION="dev"
CLEAN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            VERSION="$2"
            shift 2
            ;;
        --clean)
            CLEAN=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--version VERSION] [--clean]"
            echo ""
            echo "Options:"
            echo "  --version VERSION   Set version string (default: dev)"
            echo "  --clean            Clean build directories before building"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Detect platform
detect_platform() {
    local os arch
    os="$(uname -s)"
    arch="$(uname -m)"

    case "$os" in
        Darwin)
            case "$arch" in
                arm64) echo "macos-arm64" ;;
                x86_64) echo "macos-x64" ;;
                *) echo "macos-unknown" ;;
            esac
            ;;
        Linux)
            case "$arch" in
                x86_64) echo "linux-x64" ;;
                aarch64) echo "linux-arm64" ;;
                *) echo "linux-unknown" ;;
            esac
            ;;
        *)
            echo "unknown-$os-$arch"
            ;;
    esac
}

PLATFORM=$(detect_platform)

echo "============================================"
echo "STaBioM Release Build"
echo "============================================"
echo "Version:  $VERSION"
echo "Platform: $PLATFORM"
echo "============================================"
echo ""

cd "$REPO_ROOT"

# Clean if requested
if [[ "$CLEAN" == "true" ]]; then
    echo "Cleaning build directories..."
    rm -rf build/ dist/ *.spec.bak
fi

# Check for PyInstaller
if ! command -v pyinstaller &>/dev/null; then
    echo "ERROR: PyInstaller not found. Install with: pip install pyinstaller"
    exit 1
fi

# Build
echo "Building with PyInstaller..."
pyinstaller stabiom.spec

# Verify build
echo ""
echo "Verifying build..."
if [[ -x "dist/stabiom/stabiom" ]]; then
    echo "Testing --help..."
    ./dist/stabiom/stabiom --help >/dev/null
    echo "Testing list..."
    ./dist/stabiom/stabiom list
    echo ""
    echo "Build verification passed!"
else
    echo "ERROR: Build failed - executable not found"
    exit 1
fi

# Create tarball
TARBALL_NAME="stabiom-${VERSION}-${PLATFORM}"
echo ""
echo "Creating tarball: ${TARBALL_NAME}.tar.gz"

cd dist
if [[ -d "$TARBALL_NAME" ]]; then
    rm -rf "$TARBALL_NAME"
fi
mv stabiom "$TARBALL_NAME"
tar -czvf "${TARBALL_NAME}.tar.gz" "$TARBALL_NAME/"

# Summary
echo ""
echo "============================================"
echo "Build Complete!"
echo "============================================"
echo ""
echo "Output: dist/${TARBALL_NAME}.tar.gz"
echo ""
echo "To test:"
echo "  cd dist/${TARBALL_NAME}"
echo "  ./stabiom --help"
echo "  ./stabiom list"
echo "  ./stabiom run -p sr_amp -i /path/to/reads/ --dry-run"
echo ""
