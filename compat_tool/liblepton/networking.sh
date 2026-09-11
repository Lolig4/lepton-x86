##!/bin/bash

function podman_ip()
{
    local PODMAN_IP="$(podman inspect -f '{{ index .Config.Labels "IP" }}' "lepton-${1:-${LEPTON_CONTEXT}}" 2>/dev/null || true)"
    if [[ -n "${PODMAN_IP}" ]]; then
        print "${PODMAN_IP}"
        return
    fi

    # Attempt to use the same IP as the default route so that applications that
    # lookup their own IP have a shareable value
    PODMAN_IP="$(ip route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}')"
    if [[ -n "${PODMAN_IP}" ]]; then
        print "${PODMAN_IP}"
        return
    fi

    # Fallback
    local FALLBACK_SUBNET="10.0.4"
    if [[ -z "${PODMAN_IP}" ]]; then
        PODMAN_IP="${FALLBACK_SUBNET}.$(($(lepton_port_offset)*4 % 256))"
        if [[ "${PODMAN_IP}" == "${FALLBACK_SUBNET}.0" ]] || [[ "${PODMAN_IP}" == "${FALLBACK_SUBNET}.255" ]]; then
            PODMAN_IP="${FALLBACK_SUBNET}.2"
        fi
    fi
    print "${PODMAN_IP}"
}

function podman_subnet()
{
    local ip="$(podman_ip)"
    print "${ip%.*}"
}

function lepton_port_offset()
{
    if [[ "${LEPTON_PORT_OFFSET:-}" == "" ]]; then
        setup_podman_port_forwards
    fi
    print "${LEPTON_PORT_OFFSET}"
}

# Collect all forwarded ADB ports
function live_port_forwarding_offsets()
{
    for CONTEXT in $(list_live_contexts); do
        local OTHER_ADB_PORT="$(adb_port "${CONTEXT}")"
        if [[ -n "${OTHER_ADB_PORT}" ]]; then
            println $((${OTHER_ADB_PORT} - 5555))
        fi
    done | sort -n
}

function podman_forward_ports()
{
    CONTEXT="${1}"
    OFFSET="${2}"

    ADB_PORT="$((5555 + ${OFFSET}))"
    export LEPTON_ADB_PORT="${ADB_PORT}"
}

function setup_podman_port_forwards()
{
    local PORT_FORWARDING_OFFSETS=( $(live_port_forwarding_offsets) )
    if [[ "${#PORT_FORWARDING_OFFSETS[@]}" == 0 ]]; then
        export LEPTON_PORT_OFFSET=0
        return
    fi

    for idx in $(seq 0 "$((${PORT_FORWARDING_OFFSETS[-1]} + 1))"); do
        # Have we found a hole in our port forwarding offsets?
        if [[ " ${PORT_FORWARDING_OFFSETS[@]} " != *" ${idx} "* ]]; then
            export LEPTON_PORT_OFFSET=${idx}
            return
        fi
    done

    die "Unable to auto-forward ports!"
}

function podman_network_options()
{
    local PODMAN_NETWORK_OPTIONS=""

    # Using a network type which works without root (pasta)

    # Most of the following options need to match what we have in
    # generate_ipconfig_txt.

    # This is how the network interface will be named inside the container.
    PODMAN_NETWORK_OPTIONS+="-I eth0"

    # For simplicity use IPv4
    PODMAN_NETWORK_OPTIONS+=" --ipv4-only"
    PODMAN_NETWORK_OPTIONS+=" --no-ndp"

    # The address of the network interface inside the container
    PODMAN_NETWORK_OPTIONS+=" -a $(podman_ip)"

    # The gateway that the network inside the container expects
    PODMAN_NETWORK_OPTIONS+=" -g $(podman_subnet).1"

    # MTU
    PODMAN_NETWORK_OPTIONS+=" -m 1500"

    # We use a static ip configuration
    PODMAN_NETWORK_OPTIONS+=" --no-dhcpv6 --no-dhcp"

    # We need to map the gateway otherwise steamclient can't connect.
    PODMAN_NETWORK_OPTIONS+=" --map-gw"

    PODMAN_NETWORK_OPTIONS+=" -t auto"
    PODMAN_NETWORK_OPTIONS+=" -u auto"
    PODMAN_NETWORK_OPTIONS+=" --no-splice"

    # Since the dns is configured to this address in generate_ipconfig_txt we
    # need to forward requests on it.
    PODMAN_NETWORK_OPTIONS+=" --dns-forward $(podman_subnet).1"

    print "--network=pasta:${PODMAN_NETWORK_OPTIONS// /,}"
}

function setup_podman_network()
{
    if is_sysbake; then
        podman_cmdline "--network=none"
    else
        setup_podman_port_forwards
        export LEPTON_GDB_PORT="${LEPTON_GDB_PORT:-$((1337 + $(lepton_port_offset)))}"
        export LEPTON_LLDB_PORT="${LEPTON_LLDB_PORT:-$((2337 + $(lepton_port_offset)))}"
        podman_cmdline "$(podman_network_options)"
        podman_cmdline "--add-host=host.containers.internal:$(podman_subnet).1"
        podman_forward_ports "${LEPTON_CONTEXT}" "$(lepton_port_offset)"
    fi
}

# Note; cannot write strings longer than 255 characters :P
function writeString()
{
    printf "\x00\x$(printf "%x" "${#1}")"
    printf "${1}"
}

function generate_ipconfig_txt()
{
    # File format version 3
    printf "\x00\x00\x00\x03"

    writeString "ipAssignment"
    writeString "STATIC"
    writeString "linkAddress"
    writeString "$(podman_ip)"
    printf "\x00\x00\x00\x$(printf "%x" "24")" # subnet mask /24
    writeString "gateway"
    printf "\x00\x00\x00\x00" # default route
    printf "\x00\x00\x00\x01" # have a gateway
    writeString "$(podman_subnet).1"
    writeString "dns"
    writeString "$(podman_subnet).1"
    writeString "proxySettings"
    writeString "NONE"
    writeString "id"
    writeString "eth0"
    writeString "eos"
}
