#!/bin/bash
# Apply the x86_64 patch set to this checkout, as commits.
#
#   .x86_scripts/apply-patches.sh            apply what is missing
#   .x86_scripts/apply-patches.sh --revert   drop the patch commits again
#
# Every patch becomes one commit, in the repository it belongs to (the device
# tree and the waydroid hardware tree are submodules).  That keeps `git log`
# and `git diff` usable during development and makes a rebase onto a newer
# upstream an ordinary git operation.

set -euo pipefail

X86_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${X86_DIR}/lepton_x86_lib.sh"

PATCH_DIR="${PROJECT_DIR}/patches"
# Subject prefix of the patch commits.  Deliberately not the prefix of the
# commit that carries these scripts: --revert drops every commit that matches.
MARKER="x86_64 patch:"

# patch file : repository it applies to
patch_target() {
    case "$(basename "$1")" in
        0002-device-*)     echo "image/android_device_waydroid_waydroid" ;;
        0006-hwcomposer-*) echo "image/android_hardware_waydroid" ;;
        *)                 echo "." ;;
    esac
}

patch_subject() {
    # 0001-compat_tool-x86_64.patch -> compat_tool x86_64
    basename "$1" .patch | sed -e 's/^[0-9]*-//' -e 's/-/ /g'
}

revert_repo() {
    local repo="$1"

    # Reverting rewrites history, which would take uncommitted work with it.
    if [[ -n "$(git -C "${repo}" status --porcelain --ignore-submodules=all)" ]]; then
        die "${repo} has uncommitted changes -- commit or stash them first"
    fi

    local subjects count oldest base
    subjects="$(git -C "${repo}" log --format='%H %s')"
    count="$(grep -c " ${MARKER}" <<< "${subjects}" || true)"
    if (( count == 0 )); then
        return 0
    fi

    # Drop the patch commits wherever they sit, keeping everything else: work
    # committed on top of the patch set is normal (these scripts are versioned
    # in the same repository).
    oldest="$(grep " ${MARKER}" <<< "${subjects}" | tail -1 | cut -d' ' -f1)"
    base="${oldest}^"
    if [[ "$(git -C "${repo}" rev-list --count "${base}..HEAD")" == "${count}" ]]; then
        # Nothing but patch commits on top, and an empty todo list makes rebase
        # refuse the job.
        git -C "${repo}" reset --hard "${base}" >/dev/null
    else
        # The subject can sit anywhere behind the hash: rebase.instructionFormat
        # is a user setting.
        GIT_SEQUENCE_EDITOR="sed -i -e '/^pick .*${MARKER}/d'" \
            git -C "${repo}" rebase -q -i "${base}" >/dev/null \
            || die "${repo}: could not drop the patch commits (rebase stopped -- resolve it by hand)"
    fi
    echo "  ${repo}: ${count} patch commit(s) dropped"
}

if [[ "${1:-}" == "--revert" ]]; then
    msg "Reverting the x86_64 patch set"
    for repo in image/android_device_waydroid_waydroid image/android_hardware_waydroid .; do
        revert_repo "${PROJECT_DIR}/${repo}"
    done
    exit 0
fi

msg "Applying the x86_64 patch set"
for patch in "${PATCH_DIR}"/*.patch; do
    repo="${PROJECT_DIR}/$(patch_target "${patch}")"
    subject="${MARKER} $(patch_subject "${patch}")"

    # Not a pipe into grep -q: it closes the pipe early, and under pipefail that
    # turns into a failed check.
    if grep -qxF "${subject}" <<< "$(git -C "${repo}" log --format=%s)"; then
        echo "  $(basename "${patch}"): already applied"
        continue
    fi
    if ! git -C "${repo}" apply --check "${patch}" 2>/dev/null; then
        die "$(basename "${patch}") does not apply to ${repo} -- upstream moved?"
    fi

    git -C "${repo}" apply "${patch}"
    # Submodule pointers are left alone: each submodule carries its own patch
    # commit, so the parent would only record a revision that exists nowhere
    # else.
    git -C "${repo}" add -A -- \
        ':(exclude)image/android_device_waydroid_waydroid' \
        ':(exclude)image/android_hardware_waydroid' \
        ':(exclude)image/android_vendor_waydroid'

    git -C "${repo}" commit -q -m "${subject}" -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
    echo "  $(basename "${patch}"): applied"
done

msg "Patch set applied"
