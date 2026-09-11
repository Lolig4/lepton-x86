#!/bin/bash

LEPTON_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
function list_live_contexts()
{
    (source "${LEPTON_DIR}/liblepton.sh"; list_live_contexts)
}
function list_contexts()
{
    (source "${LEPTON_DIR}/liblepton.sh"; list_contexts)
}
function list_android_games()
{
    (source "${LEPTON_DIR}/liblepton.sh"; list_android_games)
}
function list_live_android_games()
{
    (source "${LEPTON_DIR}/liblepton.sh"; list_live_android_games "$1")
}

_lepton_completions()
{
    local cur="${COMP_WORDS[COMP_CWORD]}"

    local LEPTON_COMMANDS=(
        start
        shell
        attach
        run
        exec
        stop
        kill
        kill_all
        cleanup
        cleanup_all
        logcat
        logsetup
        install_app
        perfetto
        ps
        list_containers
        bootchart
        collect_logs
        help
        unreal_vr_test
        sysbake
        extract
        start_early_debug

        # Debugging commands
        gdb_server
        lldb_server
        gdb_attach
        lldb_attach
        kill_gdb_server
        kill_lldb_server

        apk_info
        version
    )

    COMP_WORDBREAKS=${COMP_WORDBREAKS//=}

    compopt +o default

    # If we're doing an `install_app`, do local file completions
    if (( "${#COMP_WORDS[@]}" == 4 )) && [[ "${COMP_WORDS[1]}" == "install_app" ]]; then
        compopt -o default
        COMPREPLY=()
        return
    fi
    # Determine the apk if there are multiple
    if (( "${#COMP_WORDS[@]}" == 4 )) && [[ "${COMP_WORDS[1]}" == "start" ]]; then
        GAME=$(echo $3 | sed "s|\\\\||g")
        if [[ "${GAME}" != *".apk" ]]; then
            while IFS= read -r app; do
                COMPREPLY+=( "$(basename "$app")" )
            done < <(
                compgen -f -- "${HOME}/.local/share/Steam/steamapps/common/${GAME}/" | grep '\.apk$'
            )
        fi
        return
    fi
    # Anything else this long gets no further completion
    if (( "${#COMP_WORDS[@]}" > 3 )) && [[ "${COMP_WORDS[1]}" != "perfetto" ]]; then
        COMPREPLY=()
        return
    elif (( "${COMP_CWORD}" >= 3 )) && [[ "${COMP_WORDS[1]}" == "perfetto" ]]; then

        if [[ $cur == --config=* ]]; then
            local value="${cur#--config=}"

            local choices=(gpu_only system)

            COMPREPLY=()

            while IFS= read -r match; do
                COMPREPLY+=( "--config=$match" )
            done < <(
                compgen -W "${choices[*]}" -- "$value"
            )

            return
        fi

        # only offer --config= once
        local has_config=0
        local word

        for word in "${COMP_WORDS[@]}"; do
            if [[ "$word" == --config=* ]]; then
                has_config=1
                break
            fi
        done

        if (( ! has_config )); then
            COMPREPLY=( $(compgen -W "--config=" -- "$cur") )
            compopt -o nospace 2>/dev/null
        else
            COMPREPLY=()
        fi

        return
    fi
    case "${COMP_WORDS[1]}" in
        start|cleanup)
            local IFS=$'\n'
            COMPREPLY+=( $(compgen -W "$(list_android_games)" -- "$cur") )

            while IFS= read -r path; do
                if [[ -d "$path" || "$path" == *.apk ]]; then
                    COMPREPLY+=( "$path" )
                fi
            done < <(compgen -f -- "$cur")

            compopt -o filenames 2>/dev/null
            ;;
    esac
    case "${COMP_WORDS[1]}" in
        apk_info|shell|attach|run|exec|kill|stop|logcat|logsetup|install_app|perfetto|extract|gdb_attach|lldb_attach|lldb_server|kill_gdb_server|kill_lldb_server)
            local IFS=$'\n'
            if [[ "${COMP_WORDS[1]}" != "apk_info" ]]; then
                COMPREPLY+=( $(compgen -W "$(list_live_android_games "$cur")" -- "$cur") )
            fi

            while IFS= read -r path; do
                if [[ -d "$path" || "$path" == *.apk ]]; then
                    COMPREPLY+=( "$path" )
                fi
            done < <(compgen -f -- "$cur")

            compopt -o filenames 2>/dev/null
            ;;
    esac
    case "${COMP_WORDS[1]}" in
        shell|attach|run|exec|kill|stop|logcat|logsetup|install_app|perfetto|extract|gdb_attach|lldb_attach|lldb_server|kill_gdb_server|kill_lldb_server)
            COMPREPLY+=( $(compgen -W "$(list_live_contexts)" -- "$cur") )
            ;;
        cleanup)
            COMPREPLY+=( $(compgen -W "$(list_contexts)" -- "$cur") )
            ;;
        start)
            ;;
        *)
            COMPREPLY+=( $(compgen -W "${LEPTON_COMMANDS[*]}" -- "$cur") )
            ;;
    esac
}
complete -F _lepton_completions lepton

alias lepton="$(dirname "${LEPTON_DIR}")/lepton"
alias cdf="cd $(dirname "${LEPTON_DIR}")"
