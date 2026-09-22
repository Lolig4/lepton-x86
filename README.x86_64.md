# Lepton on x86_64

Lepton only ships an `aarch64` target, because it was written for the Steam
Frame.  Everything it is built from -- LineageOS 18.1, the Waydroid device
tree, Valve's patch set -- also supports x86_64, so the port is a new product
target plus a handful of architecture fixes.  Those live in `patches/`, the
build steps in `.x86_scripts/`, next to Valve's own `.ci_scripts/`.

The result is a Steam compatibility tool in
`~/.local/share/Steam/compatibilitytools.d/lepton-x86_64`: add an `.apk` as a
non-Steam game, set its compatibility tool, and it runs in an Android container
in a window of its own.

Upstream is <https://gitlab.steamos.cloud/frame-public/lepton> (this checkout is
at `f64fb91`); it is not configured as a remote here.  To follow it:

    git remote add upstream https://gitlab.steamos.cloud/frame-public/lepton.git
    .x86_scripts/apply-patches.sh --revert && git pull upstream main && .x86_scripts/apply-patches.sh

## Building

    .x86_scripts/install-dependencies.sh    # host packages, needs root
    .x86_scripts/build-all.sh               # -> lepton-x86_64-<version>.tar.zst

`build-all.sh` never runs Lepton, so it works on a headless build machine.  On
the machine that will run the container:

    TARBALL=lepton-x86_64-<version>.tar.zst .x86_scripts/install-steam-tool.sh

That unpacks the tarball and installs everything into
`compatibilitytools.d/lepton-x86_64`.

Optional, before installing: `.x86_scripts/build-sysbake-x86_64.sh` boots
Android once and keeps the resulting `/data`.  Without it every container start
redoes Android's first boot (package scanning, dexopt) instead of coming up in
a few seconds.

The Android image is the only expensive step (tens of GB of sources, hours of
compiling, well over 100 GB of disk).  It is built once and then reused; every
later run of `build-all.sh` skips it.  To force it:

    CLEAN=1 .x86_scripts/build-all.sh

`CLEAN=1` works per step as well, and means the same everywhere: redo this even
though its result is already there.

Building on one machine and running on another is the normal case -- the image
does not depend on where it was built:

    IMAGES_FROM=buildhost:/srv/lepton/image .x86_scripts/build-all.sh

### Steps

| Script | Result |
| --- | --- |
| `apply-patches.sh` | the x86_64 patch set, as commits |
| `build-rootfs-x86_64.sh` | `image/system.img`, `image/vendor.img` |
| `build-hwcomposer.sh` | just `hwcomposer.waydroid.so`, into the unpacked rootfs |
| `prepare-rootfs-x86_64.sh` | `compat_tool/images/rootfs` (plus the ARM bridge) |
| `build-compat_tool-x86_64.sh` | `install-x86_64/`, a runnable tool |
| `package-compat_tool-x86_64.sh` | `lepton-x86_64-<version>.tar.zst`, for transport |
| `build-sysbake-x86_64.sh` | `install-x86_64/sysbake`, a pre-booted `/data` |
| `install-steam-tool.sh` | `compatibilitytools.d/lepton-x86_64`, self contained |

Changing the hwcomposer -- the part that turns Android's layers into Wayland
windows, and the part most likely to need work -- does not need an image build:

    .x86_scripts/build-hwcomposer.sh
    .x86_scripts/build-compat_tool-x86_64.sh
    .x86_scripts/package-compat_tool-x86_64.sh

### Useful variables

| Variable | Meaning |
| --- | --- |
| `CLEAN=1` | redo the step even if its result exists |
| `JOBS` | parallelism of the AOSP build (default: all cores) |
| `CCACHE_SIZE` | ccache limit inside the builder (default: 40G) |
| `IMAGES_FROM` | take `system.img`/`vendor.img` from there instead of building |
| `ARM_TRANSLATION=false` | leave Google's ARM translator out |
| `TARBALL` | install from a build machine's tarball instead of a local build |
| `STEAM_TOOL_DIR` | install somewhere other than Steam's directory |

## The patch set

`apply-patches.sh` applies each patch as one commit, in the repository it
belongs to (two of them are in submodules).  `--revert` drops those commits
again, so upstream can be updated and the set rebased like any other branch.

| Patch | What it does |
| --- | --- |
| `0001-compat_tool-x86_64` | the compat tool itself: architecture handling, x86_64 graphics properties (mesa/radeon/gbm), optional SteamVR and fossilize, app-only mode (`LEPTON_APP_ONLY`), headless install (`LEPTON_INSTALL_ONLY`), stop the container when the app's window closes |
| `0002-device-lepton_x86_64_only` | a new product, `lepton_x86_64_only`: the Waydroid device tree without the Qualcomm parts, with mesa, and with partition sizes that fit |
| `0003-build-job-limit` | `LEPTON_JOBS` instead of an unconditional `nproc`, so a build can be kept from filling the machine |
| `0004-builder-glslang-for-radv` | the builder image gets a glslang new enough for Mesa 26 |
| `0005-mesa-radv-android11-camera-mask` | one constant Android 11 does not have yet, which RADV needs |
| `0006-hwcomposer-wayland-fixes` | the hwcomposer: wait for the first `configure` of every window (strict compositors kill the client otherwise), calibrate from `wl_output` instead of a throwaway window (no fullscreen flash at startup), and give each app a window of its own size with a title bar from the desktop, movable and resizable |

## Status

Works: apps install once, start from Steam in a few seconds, run in their own
window without Android's home screen or system bars, and can be moved and
resized.  ARM apps run through `ndk_translation` (arm64 only; this image is
64-bit).

Not there yet: the GPU path.  Rendering is software (swiftshader), because the
container dies during installation when RADV is used.  VR is out of scope --
there is no SteamVR runtime to mount on a desktop.
