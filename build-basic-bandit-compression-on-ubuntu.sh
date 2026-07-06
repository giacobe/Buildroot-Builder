#!/usr/bin/env sh
set -eu

PACKAGE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
if [ -z "${POLYLINUX_BASELINE_VERSION+x}" ]; then POLYLINUX_BASELINE_VERSION="basic-bandit-compression-v1"; fi
if [ -z "${BUILDROOT_DIR+x}" ]; then BUILDROOT_DIR="$HOME/buildroot-2025.02.15"; fi
if [ -z "${POLYLINUX_BUILD_WORKDIR+x}" ]; then POLYLINUX_BUILD_WORKDIR="$HOME/polylinux-buildroot-$POLYLINUX_BASELINE_VERSION-work"; fi
if [ -z "${POLYLINUX_ARTIFACT_DIR+x}" ]; then POLYLINUX_ARTIFACT_DIR="$PACKAGE_DIR/artifacts/$POLYLINUX_BASELINE_VERSION"; fi
if [ -z "${POLYLINUX_DEFCONFIG+x}" ]; then POLYLINUX_DEFCONFIG="$PACKAGE_DIR/configs/polylinux-v86-basic-bandit-compression_defconfig"; fi
if [ -z "${POLYLINUX_FRAGMENT+x}" ]; then POLYLINUX_FRAGMENT="$PACKAGE_DIR/configs/basic-bandit-compression-features.fragment"; fi
if [ -z "${POLYLINUX_COMMANDS_FILE+x}" ]; then POLYLINUX_COMMANDS_FILE="$PACKAGE_DIR/manifest/basic-bandit-compression-required-commands.txt"; fi
CHECKER="$PACKAGE_DIR/scripts/check-rootfs-commands.py"
OUTPUT_DIR="$POLYLINUX_BUILD_WORKDIR/output"

required_symbols='
BR2_PACKAGE_BASH
BR2_PACKAGE_BUSYBOX_SHOW_OTHERS
BR2_PACKAGE_FILE
BR2_PACKAGE_FINDUTILS
BR2_PACKAGE_GREP
BR2_PACKAGE_GAWK
BR2_PACKAGE_SED
BR2_PACKAGE_COREUTILS
BR2_PACKAGE_SHADOW
BR2_PACKAGE_BC
BR2_TOOLCHAIN_BUILDROOT_CXX
BR2_INSTALL_LIBSTDCPP
BR2_PACKAGE_BINUTILS
BR2_PACKAGE_BINUTILS_TARGET
BR2_PACKAGE_VIM
BR2_PACKAGE_GZIP
BR2_PACKAGE_BZIP2
BR2_PACKAGE_XZ
BR2_PACKAGE_TAR
BR2_PACKAGE_ZIP
BR2_PACKAGE_UNZIP
BR2_PACKAGE_LZ4
BR2_PACKAGE_LZ4_PROGS
BR2_PACKAGE_ZSTD
BR2_PACKAGE_BROTLI
BR2_PACKAGE_LZOP
BR2_PACKAGE_LRZIP
BR2_PACKAGE_P7ZIP
BR2_PACKAGE_P7ZIP_7ZA
BR2_PACKAGE_PIGZ
'

if [ ! -d "$BUILDROOT_DIR" ]; then
  echo "BUILDROOT_DIR does not exist: $BUILDROOT_DIR" >&2
  echo "Set BUILDROOT_DIR to your Buildroot 2025.02.15 source tree and run again." >&2
  exit 2
fi

if [ ! -f "$BUILDROOT_DIR/Makefile" ] || [ ! -d "$BUILDROOT_DIR/package" ]; then
  echo "BUILDROOT_DIR does not look like a Buildroot source tree: $BUILDROOT_DIR" >&2
  exit 2
fi

for required_file in "$POLYLINUX_DEFCONFIG" "$POLYLINUX_FRAGMENT" "$POLYLINUX_COMMANDS_FILE" "$CHECKER"; do
  if [ ! -f "$required_file" ]; then
    echo "Missing required file: $required_file" >&2
    exit 2
  fi
done

if [ -z "${JOBS+x}" ]; then JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf 2)"; fi

mkdir -p "$POLYLINUX_BUILD_WORKDIR" \
  "$POLYLINUX_ARTIFACT_DIR/configs" \
  "$POLYLINUX_ARTIFACT_DIR/images" \
  "$POLYLINUX_ARTIFACT_DIR/logs" \
  "$POLYLINUX_ARTIFACT_DIR/manifest"

if [ -e "$OUTPUT_DIR" ]; then
  previous="$POLYLINUX_BUILD_WORKDIR/output.$POLYLINUX_BASELINE_VERSION.previous.$(date +%Y%m%d-%H%M%S)"
  echo "Existing output directory found. Moving it to $previous"
  mv "$OUTPUT_DIR" "$previous"
fi

cp "$POLYLINUX_DEFCONFIG" "$POLYLINUX_ARTIFACT_DIR/configs/starting.defconfig"
cp "$POLYLINUX_FRAGMENT" "$POLYLINUX_ARTIFACT_DIR/configs/requested-features.fragment"
cp "$POLYLINUX_COMMANDS_FILE" "$POLYLINUX_ARTIFACT_DIR/manifest/required-commands.txt"
printf '%s\n' "Buildroot 2025.02.15" > "$POLYLINUX_ARTIFACT_DIR/buildroot-version.txt"

echo "Using Buildroot source: $BUILDROOT_DIR"
echo "Using package directory: $PACKAGE_DIR"
echo "Using output directory: $OUTPUT_DIR"
echo "Using artifact directory: $POLYLINUX_ARTIFACT_DIR"
echo "Using baseline version: $POLYLINUX_BASELINE_VERSION"
echo "Using jobs: $JOBS"

make -C "$BUILDROOT_DIR" O="$OUTPUT_DIR" BR2_DEFCONFIG="$POLYLINUX_ARTIFACT_DIR/configs/starting.defconfig" defconfig
make -C "$BUILDROOT_DIR" O="$OUTPUT_DIR" olddefconfig

missing_symbols=""
for symbol in $required_symbols; do
  if ! grep -q "^$symbol=y$" "$OUTPUT_DIR/.config"; then
    missing_symbols="$missing_symbols $symbol"
  fi
done

if [ -n "$missing_symbols" ]; then
  echo "These requested Buildroot symbols did not survive olddefconfig:$missing_symbols" >&2
  echo "The full .config is at $OUTPUT_DIR/.config; inspect the missing symbols with make menuconfig search." >&2
  exit 3
fi

make -C "$BUILDROOT_DIR" O="$OUTPUT_DIR" -j"$JOBS" 2>&1 | tee "$POLYLINUX_ARTIFACT_DIR/logs/build.log"
make -C "$BUILDROOT_DIR" O="$OUTPUT_DIR" savedefconfig

cp "$OUTPUT_DIR/images/bzImage" "$POLYLINUX_ARTIFACT_DIR/images/$POLYLINUX_BASELINE_VERSION-bzImage"
cp "$OUTPUT_DIR/images/rootfs.cpio.gz" "$POLYLINUX_ARTIFACT_DIR/images/$POLYLINUX_BASELINE_VERSION-rootfs.cpio.gz"
cp "$OUTPUT_DIR/.config" "$POLYLINUX_ARTIFACT_DIR/configs/final-buildroot.config"
cp "$OUTPUT_DIR/defconfig" "$POLYLINUX_ARTIFACT_DIR/configs/final-buildroot.defconfig"

for config in "$OUTPUT_DIR"/build/linux-*/.config; do
  [ -f "$config" ] || continue
  cp "$config" "$POLYLINUX_ARTIFACT_DIR/configs/final-linux.config"
  break
done

sha256sum "$POLYLINUX_ARTIFACT_DIR/images/$POLYLINUX_BASELINE_VERSION-bzImage" \
  "$POLYLINUX_ARTIFACT_DIR/images/$POLYLINUX_BASELINE_VERSION-rootfs.cpio.gz" \
  > "$POLYLINUX_ARTIFACT_DIR/manifest/artifact-sha256.txt"

python3 "$CHECKER" "$POLYLINUX_ARTIFACT_DIR/images/$POLYLINUX_BASELINE_VERSION-rootfs.cpio.gz" \
  --commands $(cat "$POLYLINUX_ARTIFACT_DIR/manifest/required-commands.txt") \
  | tee "$POLYLINUX_ARTIFACT_DIR/logs/validation.log"

cat > "$POLYLINUX_ARTIFACT_DIR/manifest/validation-notes.md" <<EOF
# $POLYLINUX_BASELINE_VERSION Validation Notes

- Includes the PolyLinux Basic runtime and setup commands.
- Includes Bandit inspection and archive commands: file, strings, base64, xxd, gzip/gunzip, bzip2/bunzip2/bzcat, xz/unxz/lzma/unlzma, and tar.
- Adds broader compression commands: zip/unzip, lz4, zstd, brotli, lzop, lrzip, 7za, and pigz.
- Command presence was checked with scripts/check-rootfs-commands.py; option compatibility should still be smoke-tested in the booted VM.
EOF

cat > "$POLYLINUX_ARTIFACT_DIR/manifest/build-summary.txt" <<EOF
Buildroot source: $BUILDROOT_DIR
Package directory: $PACKAGE_DIR
Output directory: $OUTPUT_DIR
Artifact directory: $POLYLINUX_ARTIFACT_DIR
Baseline version: $POLYLINUX_BASELINE_VERSION
Defconfig: $POLYLINUX_DEFCONFIG
Feature fragment: $POLYLINUX_FRAGMENT
Command manifest: $POLYLINUX_COMMANDS_FILE
Jobs: $JOBS
Outputs:
  images/$POLYLINUX_BASELINE_VERSION-bzImage
  images/$POLYLINUX_BASELINE_VERSION-rootfs.cpio.gz
EOF

echo "Done. PolyLinux Basic plus Bandit artifacts are in:"
echo "  $POLYLINUX_ARTIFACT_DIR/images/$POLYLINUX_BASELINE_VERSION-bzImage"
echo "  $POLYLINUX_ARTIFACT_DIR/images/$POLYLINUX_BASELINE_VERSION-rootfs.cpio.gz"