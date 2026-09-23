#!/bin/bash
# Install the assembled tool as a Steam compatibility tool, self contained.
#
#   .x86_scripts/install-steam-tool.sh                     into ~/.local/share/Steam/…
#   TARBALL=<file> .x86_scripts/install-steam-tool.sh      from a build machine's tarball
#   STEAM_TOOL_DIR=/path .x86_scripts/install-steam-tool.sh   somewhere else
#
# Everything the tool needs at runtime ends up in one directory: the scripts,
# the Android rootfs, the bake, the SELinux module and a host setup script.  It
# can be copied to another machine as it is.

set -euo pipefail

X86_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${X86_DIR}/lepton_x86_lib.sh"

# A build machine hands over a tarball; unpack it in place of building here.
if [[ -n "${TARBALL:-}" ]]; then
    [[ -f "${TARBALL}" ]] || die "no such file: ${TARBALL}"
    msg "Unpacking ${TARBALL}"
    require_cmd zstd
    rm -rf "${COMPAT_TOOL_DIR}"
    mkdir -p "${COMPAT_TOOL_DIR}"
    tar --zstd --xattrs -xf "${TARBALL}" -C "${COMPAT_TOOL_DIR}"
    if command -v getenforce >/dev/null && [[ "$(getenforce)" == "Enforcing" ]]; then
        chcon -R -t container_file_t "${COMPAT_TOOL_DIR}"
    fi
fi

[[ -x "${COMPAT_TOOL_DIR}/lepton" ]] || die "no compat tool yet (run: .x86_scripts/build-compat_tool-x86_64.sh, or pass TARBALL=)"
[[ -d "${COMPAT_TOOL_DIR}/images/rootfs" ]] || die "no rootfs in the compat tool (run: .x86_scripts/prepare-rootfs-x86_64.sh)"

# No system bake here: build-sysbake-x86_64.sh does that on demand.  Lepton
# refuses to start without one, so the bake travels in the tarball.

msg "Installing into ${STEAM_TOOL_DIR}"
rm -rf "${STEAM_TOOL_DIR}"
mkdir -p "${STEAM_TOOL_DIR}"

# Lepton finds its rootfs and bake relative to itself (liblepton/../images,
# liblepton/../sysbake), so the whole thing can simply live here.
# --reflink: free on btrfs/xfs, so the 1.5 GB rootfs costs no extra space.
cp -a --reflink=auto "${COMPAT_TOOL_DIR}/liblepton" "${COMPAT_TOOL_DIR}/images" "${STEAM_TOOL_DIR}/"
cp -a "${COMPAT_TOOL_DIR}/toolmanifest.vdf" "${COMPAT_TOOL_DIR}/version.txt" "${STEAM_TOOL_DIR}/"
cp -a "${COMPAT_TOOL_DIR}/LICENSE.md" "${COMPAT_TOOL_DIR}/LICENSES" "${STEAM_TOOL_DIR}/"
cp -a "${COMPAT_TOOL_DIR}/lepton" "${STEAM_TOOL_DIR}/lepton.bin"
# Lepton restores the bake's extended attributes from sysbake.xattrs on every
# start, so both travel together.
if [[ -d "${COMPAT_TOOL_DIR}/sysbake" ]]; then
    cp -a --reflink=auto "${COMPAT_TOOL_DIR}/sysbake" "${STEAM_TOOL_DIR}/"
    if [[ -f "${COMPAT_TOOL_DIR}/sysbake.xattrs" ]]; then
        cp -a "${COMPAT_TOOL_DIR}/sysbake.xattrs" "${STEAM_TOOL_DIR}/"
    else
        warn "the bake has no sysbake.xattrs -- Android will wipe its own app data on the first start"
    fi
fi
cp -a "${X86_DIR}/selinux" "${STEAM_TOOL_DIR}/"
cp -a "${X86_DIR}/install-arm-translation.sh" "${STEAM_TOOL_DIR}/"

# The SELinux module is text in the repository; compile it here so the bundle
# carries a loadable policy.
if command -v checkmodule >/dev/null && command -v semodule_package >/dev/null; then
    ( cd "${STEAM_TOOL_DIR}/selinux" \
      && checkmodule -M -m -o lepton_binder.mod lepton_binder.te \
      && semodule_package -o lepton_binder.pp -m lepton_binder.mod ) >/dev/null
else
    warn "checkmodule/semodule_package missing -- shipping the policy source only"
fi

# Steam runs <dir>/lepton; this wrapper adds the host defaults and keeps them
# editable in one place.
cat > "${STEAM_TOOL_DIR}/lepton" <<'WRAP'
#!/bin/bash
# Entry point Steam invokes:  lepton <verb> -- <app.apk>
DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
[[ -f "${DIR}/lepton.conf" ]] && . "${DIR}/lepton.conf"
exec "${DIR}/lepton.bin" "$@"
WRAP
chmod +x "${STEAM_TOOL_DIR}/lepton"

cat > "${STEAM_TOOL_DIR}/lepton.conf" <<'CONF'
# Defaults for this installation. Edit freely; every value can also be set in
# the environment before starting.

# Hardware rendering through Mesa (radeonsi on AMD).  Set to true to fall back
# to swiftshader if a machine has no working GPU path.
export LEPTON_FORCE_SOFTWARE="${LEPTON_FORCE_SOFTWARE:-false}"

# Show the app's 2D window at all (Lepton is headless by default, for VR).
export LEPTON_SHOW_FLATSCREEN="${LEPTON_SHOW_FLATSCREEN:-true}"

# Show only the app: no Android home screen, status bar or navigation bar.
# Set to false for the full Android UI in one window.
export LEPTON_APP_ONLY="${LEPTON_APP_ONLY:-true}"

# Give the app a window of its own size with a title bar from the desktop,
# instead of a transparent overlay the size of the whole screen.
export LEPTON_CROP_APP_WINDOWS="${LEPTON_CROP_APP_WINDOWS:-true}"

# Android's on-screen keyboard.  The desktop has a real one and Lepton passes
# it through, so the soft keyboard only covers the app -- in a window of its
# own, which arrives on the desktop as an empty second window, and its first
# appearance stalls the app while it loads its dictionaries.  Set to true if a
# machine has no keyboard.
export LEPTON_SOFT_KEYBOARD="${LEPTON_SOFT_KEYBOARD:-false}"
CONF

cat > "${STEAM_TOOL_DIR}/compatibilitytool.vdf" <<'VDF'
"compatibilitytools"
{
  "compat_tools"
  {
    "lepton-x86_64"
    {
      "install_path" "."
      "display_name" "Lepton (x86_64)"
      "from_oslist"  "windows"
      "to_oslist"    "linux"
    }
  }
}
VDF

cat > "${STEAM_TOOL_DIR}/setup-host.sh" <<'SETUP'
#!/bin/bash
# Prepare this machine to run the Lepton compat tool. Needs root.
#
#   ./setup-host.sh            install packages, SELinux module, labels
#   ./setup-host.sh --remove   remove the SELinux module again
set -euo pipefail
DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# The bake's extended attributes are what tells Android which storage of a
# package is the active one.  A tarball unpacked without --xattrs loses them;
# Lepton restores them from sysbake.xattrs at every start, so nothing has to
# happen here.

[[ $EUID -eq 0 ]] || exec sudo -- "$0" "$@"

if [[ "${1:-}" == "--remove" ]]; then
    semodule -r lepton_binder 2>/dev/null && echo "==> SELinux module removed"
    exit 0
fi

echo "==> Packages"
if command -v dnf >/dev/null; then
    dnf install -y podman catatonit inotify-tools android-tools attr
elif command -v apt-get >/dev/null; then
    apt-get update && apt-get install -y podman catatonit inotify-tools adb attr
elif command -v pacman >/dev/null; then
    pacman -Sy --noconfirm podman catatonit inotify-tools android-tools attr
else
    echo "unknown package manager -- install podman, catatonit, inotify-tools, attr and adb yourself" >&2
fi

# Android's servicemanager has to become the binder context manager inside the
# container; SELinux policies do not grant that to container domains.
if command -v getenforce >/dev/null && [[ "$(getenforce)" != "Disabled" ]]; then
    if [[ -f "${DIR}/selinux/lepton_binder.pp" ]]; then
        echo "==> SELinux module"
        semodule -i "${DIR}/selinux/lepton_binder.pp"
    fi
    echo "==> Labelling the tool for container access"
    chcon -R -t container_file_t "${DIR}"
fi

echo "==> Kernel check"
grep -qw binder /proc/filesystems && echo "  binderfs: ok" \
    || echo "  binderfs MISSING -- the kernel needs CONFIG_ANDROID_BINDERFS" >&2

echo "==> Done. Restart Steam, add the .apk as a non-Steam game and set its"
echo "    compatibility tool to 'Lepton (x86_64)'."
SETUP
chmod +x "${STEAM_TOOL_DIR}/setup-host.sh"

cat > "${STEAM_TOOL_DIR}/README.md" <<'DOC'
# Lepton (x86_64)

Valve's Lepton -- the Android container behind Steam Frame games -- ported to
x86_64 and packaged as a Steam compatibility tool. Everything needed at runtime
is in this directory: the tool, an Android 11 (SDK 30) x86_64 root filesystem,
and a pre-baked `/data` so the container boots in a few seconds.

## Deploying to another machine

    rsync -aHX lepton-x86_64/ user@host:~/.local/share/Steam/compatibilitytools.d/lepton-x86_64/
    ssh user@host ~/.local/share/Steam/compatibilitytools.d/lepton-x86_64/setup-host.sh

`-X` matters: the bake carries extended attributes that tell Android which
storage of a package is in use, and a copy without them makes Android wipe its
own app data on the first start. `sysbake.xattrs` is the repair kit -- Lepton
restores from it at every start.

`setup-host.sh` installs podman, inotify-tools, attr and adb, loads the SELinux
module and labels this directory. The host kernel needs binderfs
(`CONFIG_ANDROID_BINDERFS`, standard on Fedora and Arch).

Then restart Steam, add the `.apk` via *Games -> Add a Non-Steam Game* (set the
file filter to "All Files"), and in its *Properties -> Compatibility* pick
**Lepton (x86_64)**.

## Settings

`lepton.conf` holds the defaults: software rendering, 2D window, app-only
display and app-sized windows. Everything else is Lepton's own, see
`lepton help`.

## ARM apps

The image is x86_64, but most Android apps ship ARM code only.  Google's
`ndk_translation` bridges that: ART loads the translator instead of the app's
`.so` and runs its ARM64 code.  `install-arm-translation.sh` adds it to the
image and announces `arm64-v8a`; `--check` shows the current state.

Only **arm64-v8a** works.  This image is 64-bit only (Lepton's own design), so
apps that ship nothing but `armeabi-v7a`/`x86` cannot be installed
(`INSTALL_FAILED_NO_MATCHING_ABIS`).

The translator is proprietary Google code taken from ChromeOS.  If this
directory already contains it (`images/rootfs/system/lib64/libndk_translation.so`)
and you pass the bundle on, strip it and let the target run the script instead.

## What this is not

VR is out of scope here: there is no SteamVR runtime to mount on a desktop.
DOC

if command -v getenforce >/dev/null && [[ "$(getenforce)" == "Enforcing" ]]; then
    chcon -R -t container_file_t "${STEAM_TOOL_DIR}"
fi

echo
echo "  $(du -sh "${STEAM_TOOL_DIR}" | cut -f1) in ${STEAM_TOOL_DIR}"
echo "  Restart Steam, then add an .apk as a non-Steam game and set its"
echo "  compatibility tool to 'Lepton (x86_64)'."
