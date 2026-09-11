#!/bin/bash

set -euo pipefail

OWD=$(pwd)

WORKDIR="/home/steamos/.local/share/Steam/steamapps/lepton"
mkdir -p "${WORKDIR}"

pushd "${WORKDIR}"

tar -xf "${OWD}"/compat_tool.tar.zst -p
tar -xf "${OWD}"/rootfs.tar.zst -p

export XDG_RUNTIME_DIR=/run/user/$(id -u)
mkdir -p $XDG_RUNTIME_DIR
chmod 700 $XDG_RUNTIME_DIR

weston --socket=gamescope-0 --backend=headless --renderer=pixman &

sleep 5

podman system reset --force

sudo touch "${OWD}/sysbake-dmesg.txt"
sudo touch "${OWD}/sysbake-logcat.txt"
sudo touch "${OWD}/lepton-sysbake-trace.txt"
sudo touch "${OWD}/lepton-logcat-trace.txt"
sudo chown steamos:steamos "${OWD}/sysbake-dmesg.txt"
sudo chown steamos:steamos "${OWD}/sysbake-logcat.txt"
sudo chown steamos:steamos "${OWD}/lepton-sysbake-trace.txt"
sudo chown steamos:steamos "${OWD}/lepton-logcat-trace.txt"

sudo mkdir -p /home/steamos/.steam
sudo touch /home/steamos/.steam/steam.pipe
sudo chown steamos:steamos -R /home/steamos/.steam

sudo chmod 777 /dev/kmsg
sudo chown steamos:steamos /dev/kmsg

sudo mkdir -p /sys/fs/cgroup
sudo mount -t cgroup2 none /sys/fs/cgroup
sudo mkdir -p /sys/fs/cgroup/lepton-sysbake
sudo chown steamos:steamos -R /sys/fs/cgroup
sudo chmod 777 -R /sys/fs/cgroup

sudo sh -c "echo $$ > /sys/fs/cgroup/lepton-sysbake/cgroup.procs"

sudo sh -c "echo "+cpu +cpuset +memory +pids" > /sys/fs/cgroup/cgroup.subtree_control"

# Makes it easier to figure out if something is wrong on gitlab ci:
(
    sudo dmesg -w > "${OWD}/sysbake-dmesg.txt"
) &
(
    while true; do
        sleep 1
        exec {xtrace_fd_logcat}> "${OWD}/lepton-logcat-trace.txt"
        export BASH_XTRACEFD="${xtrace_fd_logcat}"
        LEPTON_DEBUG=true ./lepton logcat sysbake > "${OWD}/sysbake-logcat.txt" || true
    done
) &

(
    while ! pidof init; do
        echo "Waiting for lepton rootfs init";
    done
    sudo strace -fF -p $(pgrep init | head -n1) -s 4096 -o "${OWD}/lepton-sysbake-strace.txt"
) &

sudo tee /etc/containers/containers.conf >/dev/null <<'EOF'
[engine]
cgroup_manager = "cgroupfs"
EOF

exec {xtrace_fd}> "${OWD}/lepton-sysbake-trace.txt"
export BASH_XTRACEFD="${xtrace_fd}"
LEPTON_ALLOW_KMSG=true LEPTON_FORCE_SOFTWARE=true LEPTON_DEBUG=true timeout 360s ./lepton sysbake

rm -f "${WORKDIR}/sysbake/lepton-onboot"
rm -f "${WORKDIR}/sysbake/lepton-on-app-exit"
# fuse-overlayfs doesn't like this directory:
rm -rf "${WORKDIR}/sysbake/ssh"
sudo mkdir -p "${OWD}"/install
sudo chown steamos:steamos -R "${OWD}"/install
cp -ra "${WORKDIR}"/sysbake "${OWD}"/install

tar --xattrs --zstd -cf "${OWD}"/install/sysbake.tar.zst -C "${WORKDIR}"/sysbake .

pushd "${WORKDIR}"
getfattr -R -d -m '-' sysbake > "${OWD}"/install/sysbake.xattrs
popd

popd

