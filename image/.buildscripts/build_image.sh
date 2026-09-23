#!/bin/bash

set -eo pipefail

ROOT_DIR="$(dirname "$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )" )"

if [ ! -f /run/.containerenv ] && [ ! -f /.dockerenv ]; then
    echo "You must run me inside podman or docker! I do things to git config --global and such, you REALLY don't want me touching your stuff."
    exit 1
fi

if [[ ! -f "${ROOT_DIR}/output/.repo/manifest.xml" ]]; then
	echo "Android source checkout not found, automatically running 'update_repositories.sh'"
	${ROOT_DIR}/.buildscripts/update_repositories.sh $@
fi

# Android loves to strip, if you aren't a fan of stripping,
# uncomment this line to make it stop.
# cp ${ROOT_DIR}/.buildscripts/strip-stub.sh ${ROOT_DIR}/output/build/soong/scripts/strip.sh

IS_CI=false
if [[ "$1" == "--ci" ]]; then
    source ~/.bashrc
    IS_CI=true
    shift
fi

pushd "${ROOT_DIR}/output" >/dev/null
    # Copy in vendored projects
    "${ROOT_DIR}/.buildscripts/copy_vendored_projects.sh"

    # Apply all our patches
    source build/envsetup.sh
    apply-waydroid-patches

    # Set target
    lunch "${1:-lineage_lepton_arm64_only-userdebug}"
    # nproc reports every host CPU, which is wrong on a memory-constrained
    # machine: AOSP's java/metalava steps need several GB each and will OOM
    # long before the cores run out.  LEPTON_JOBS caps it.
    num_procs=${LEPTON_JOBS:-$(nproc)}
    make installclean -j${num_procs}
    if [[ "$IS_CI" == "true" ]]; then
        echo "Starting build... (logs will be in output/out/verbose.log.gz)"
        make systemimage vendorimage -j${num_procs} | grep --line-buffered -o "[0-9]\+%" | stdbuf -oL -eL uniq
    else
        make systemimage vendorimage -j${num_procs}
    fi
    ./prebuilts/python/linux-x86/2.7.5/bin/python build/tools/generate-notice-files.py -s "${OUT}/obj/NOTICE_FILES/src" --title "Lepton Android Licenses" --text "${OUT}/NOTICE.txt"

    # Convert sparse images to dense images that we can mount.  Place them in our root directory.
    rm -f ${ROOT_DIR}/system.img ${ROOT_DIR}/vendor.img
    simg2img ${OUT}/system.img ${ROOT_DIR}/system.img
    simg2img ${OUT}/vendor.img ${ROOT_DIR}/vendor.img
    tar --zstd -cf "${ROOT_DIR}/../symbols.tar.zst" -C "${OUT}/symbols" .
    cp "${OUT}"/NOTICE.txt ${ROOT_DIR}
popd >/dev/null
