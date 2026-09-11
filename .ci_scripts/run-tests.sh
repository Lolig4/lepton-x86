#!/bin/bash

set -euo pipefail

OWD=$(pwd)

WORKDIR="/home/steamos/.local/share/Steam/steamapps/lepton"
mkdir -p "${WORKDIR}"

pushd "${WORKDIR}"

tar -xf "${OWD}"/compat_tool.tar.zst -p
tar -xf "${OWD}"/rootfs.tar.zst -p
mkdir -p sysbake
tar --xattrs -xf "${OWD}"/install/sysbake.tar.zst -p -C sysbake
cp "${OWD}"/install/sysbake.xattrs .
cp -ra "${OWD}"/tests .

export XDG_RUNTIME_DIR=/run/user/$(id -u)
mkdir -p $XDG_RUNTIME_DIR
chmod 700 $XDG_RUNTIME_DIR

weston --socket=gamescope-0 --backend=headless --renderer=pixman &

sleep 5

sudo mkdir -p /home/steamos/.steam
sudo touch /home/steamos/.steam/steam.pipe
sudo chown steamos:steamos -R /home/steamos/.steam

mkdir -p $XDG_RUNTIME_DIR/pulse/
# TODO audio
touch $XDG_RUNTIME_DIR/pulse/native

podman system reset --force

/usr/share/deckard/steamvr_first_init.sh

mkdir -p /home/steamos/.local/share/Steam/config
mkdir -p /home/steamos/.local/share/Steam/logs

# Makes it easier to figure out if something is wrong on gitlab ci:
export LEPTON_ALLOW_KMSG=true
sudo chmod 777 /dev/kmsg
sudo chown steamos:steamos /dev/kmsg

# We need to run with sw graphics on gitlab ci:
export LEPTON_FORCE_SOFTWARE=true

sudo mkdir -p /sys/fs/cgroup
sudo mount -t cgroup2 none /sys/fs/cgroup

sudo mkdir -p /sys/fs/cgroup/lepton-dev
sudo mkdir -p /sys/fs/cgroup/lepton-test-apk.apk
sudo mkdir -p /sys/fs/cgroup/lepton-steamlaunch-testapp
sudo mkdir -p /sys/fs/cgroup/lepton-steamlaunch-testapp2
sudo mkdir -p /sys/fs/cgroup/lepton-early_debug
sudo mkdir -p /sys/fs/cgroup/lepton-bootchart
sudo mkdir -p /sys/fs/cgroup/lepton-steamlaunch-3418470
sudo mkdir -p /sys/fs/cgroup/lepton-test-vulkan.apk
 
sudo chown steamos:steamos -R /sys/fs/cgroup
sudo chmod 777 -R /sys/fs/cgroup
 
sudo sh -c "echo $$ > /sys/fs/cgroup/lepton-dev/cgroup.procs"
sudo sh -c "echo $$ > /sys/fs/cgroup/lepton-test-apk.apk/cgroup.procs"
sudo sh -c "echo $$ > /sys/fs/cgroup/lepton-steamlaunch-testapp/cgroup.procs"
sudo sh -c "echo $$ > /sys/fs/cgroup/lepton-steamlaunch-testapp2/cgroup.procs"
sudo sh -c "echo $$ > /sys/fs/cgroup/lepton-early_debug/cgroup.procs"
sudo sh -c "echo $$ > /sys/fs/cgroup/lepton-bootchart/cgroup.procs"
sudo sh -c "echo $$ > /sys/fs/cgroup/lepton-steamlaunch-3418470/cgroup.procs"
sudo sh -c "echo $$ > /sys/fs/cgroup/lepton-test-vulkan.apk/cgroup.procs"

sudo sh -c "echo "+cpu +cpuset +memory +pids" > /sys/fs/cgroup/cgroup.subtree_control"

sudo tee /etc/containers/containers.conf >/dev/null <<'EOF'
[engine]
cgroup_manager = "cgroupfs"
EOF

sudo touch "${OWD}/test-output.log"
sudo chown steamos:steamos "${OWD}/test-output.log"
export TEST_LOGFILE=${OWD}/test-output.log

sudo touch "${OWD}/test-trace.log"
sudo chown steamos:steamos "${OWD}/test-trace.log"
exec {xtrace_fd}> "${OWD}/test-trace.log"
export BASH_XTRACEFD="${xtrace_fd}"
export LEPTON_DEBUG=true

sudo touch "${OWD}/test-dmesg.log"
sudo chown steamos:steamos "${OWD}/test-dmesg.log"

# Makes it easier to figure out if something is wrong on gitlab ci:
(
    sudo dmesg -w > "${OWD}/test-dmesg.log"
) &

export TEST_PREFIX="TEST$1 "
case "$1" in
    1)
        ${OWD}/tests/test-dev-container-startup.sh
        ;;
    2)
        ${OWD}/tests/test-two-containers.sh
        ;;
    3)
        ${OWD}/tests/test-data-persistence.sh
        ;;
    4)
        ${OWD}/tests/test-cli-usage.sh
        ;;
    5)
        ${OWD}/tests/test-cli-debugging-usage.sh
        ;;
    6)
        ${OWD}/tests/test-network.sh
        ;;
    7)
        ${OWD}/tests/test-vulkan-configuration.sh
        ;;
    8)
        ${OWD}/tests/test-screen-contents.sh
        ;;
    9)
        ${OWD}/tests/test-app-timeout.sh
        ;;
    10)
        ${OWD}/tests/test-app-version.sh
        ;;
    11)
        ${OWD}/tests/test-proxy.sh
        ;;
    1[2-9]|2[0-9]|3[0-1])
        ${OWD}/tests/test-repeated-start.sh
        ;;
    32)
        ${OWD}/tests/test-realpath.sh
        ;;
esac

cat ${TEST_LOGFILE}

popd

