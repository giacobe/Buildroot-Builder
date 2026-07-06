# PolyLinux Basic + Bandit Compression VM Build Package

Copy this entire folder to the Ubuntu VM that has Buildroot 2025.02.15.

Expected folder contents:

```text
basic-bandit-compression-v1-vm-package/
  build-basic-bandit-compression-on-ubuntu.sh
  configs/
    polylinux-v86-basic-bandit-compression_defconfig
    basic-bandit-compression-features.fragment
  manifest/
    basic-bandit-compression-required-commands.txt
  scripts/
    check-rootfs-commands.py
```

Run on the VM:

```sh
cd basic-bandit-compression-v1-vm-package
chmod +x build-basic-bandit-compression-on-ubuntu.sh
BUILDROOT_DIR=/home/nick/buildroot-2025.02.15 ./build-basic-bandit-compression-on-ubuntu.sh
```

Outputs are written by default to:

```text
basic-bandit-compression-v1-vm-package/artifacts/basic-bandit-compression-v1/
  images/basic-bandit-compression-v1-bzImage
  images/basic-bandit-compression-v1-rootfs.cpio.gz
  configs/final-buildroot.config
  configs/final-buildroot.defconfig
  configs/final-linux.config
  logs/build.log
  logs/validation.log
  manifest/artifact-sha256.txt
  manifest/required-commands.txt
```

This package includes bzip2 compression support only. It does not add encryption packages.