#!/usr/bin/env zsh
# em.zsh - Launcher for the Scheme-powered shemacs editor (zsh native)
#
# Source this file in your .zshrc:  source /path/to/em.zsh
# Then run:  em [filename]
# Or run standalone:  zsh em.zsh [filename]
#
# All editor logic is in em.scm (Scheme), AOT-compiled to native zsh via
# bs-compile-zsh (from bs.sh).  On first run this file compiles em.scm and
# caches the result as em.scm.zsh.cache; subsequent runs source the cache
# directly — no interpreter overhead at runtime.
#
# Requires sheme to be installed: https://github.com/jordanhubbard/sheme
#   Install:  cd ~/src/sheme && make install   (puts ~/.bs.sh and ~/.bs.zsh in place)
#   Or dev layout: shemacs/ and sheme/ are siblings on the filesystem.

# Include guard: skip re-sourcing, but allow standalone execution
if [[ -n "${_SHEMACS_ZSH_LOADED:-}" && "${(%):-%N}" != "$0" ]]; then
    return 0 2>/dev/null
fi
_SHEMACS_ZSH_LOADED=1

em() {
    local _em_script_dir
    _em_script_dir="${${(%):-%N}:A:h}" 2>/dev/null || _em_script_dir="${0:A:h}"

    # Find bs.sh (needed for the AOT compiler bs-compile-zsh)
    local _em_bs_path=""
    local -a _em_bs_candidates=()
    for _bs_candidate in \
            "$HOME/.bs.sh" \
            "${_em_script_dir}/../sheme/bs.sh" \
            /usr/local/lib/sheme/bs.sh \
            /opt/sheme/bs.sh; do
        [[ -n "$_bs_candidate" && -f "$_bs_candidate" ]] || continue
        _em_bs_candidates+=("$_bs_candidate")
        [[ -z "$_em_bs_path" ]] && _em_bs_path="$_bs_candidate"
    done

    if (( ${#_em_bs_candidates[@]} == 0 )); then
        print "em: cannot find bs.sh — install sheme: https://github.com/jordanhubbard/sheme" >&2
        return 1
    fi

    # Find em.scm: prefer ~/.em.scm (user override), then alongside this script.
    local _em_scm_file
    if [[ -f "$HOME/.em.scm" ]]; then
        _em_scm_file="$HOME/.em.scm"
    elif [[ -n "$_em_script_dir" && -f "$_em_script_dir/em.scm" ]]; then
        _em_scm_file="$_em_script_dir/em.scm"
    else
        print "em: cannot find em.scm" >&2
        return 1
    fi

    # AOT-compiled zsh cache (parallel to em.scm.cache for bash)
    local _em_cache_file="${_em_scm_file}.zsh.cache"

    # Check if cache is fresh; source it if so
    if [[ -f "$_em_cache_file" \
          && "$_em_cache_file" -nt "$_em_scm_file" \
          && "$_em_cache_file" -nt "$_em_bs_path" ]] \
       && source "$_em_cache_file" && (( ${+functions[em_main]} )); then
        : # AOT cache loaded
    else
        # Need to compile
        if [[ ! -f "$_em_cache_file" ]]; then
            printf "em: First run — compiling Scheme to zsh (this may take a moment).\n" >&2
            printf "em: Subsequent runs use the cache and start instantly.\n" >&2
        else
            printf "em: Cache is stale; recompiling.\n" >&2
        fi

        # Source bs.sh to get bs-compile-zsh
        local _em_compiled=""
        for _bs_candidate in "${_em_bs_candidates[@]}"; do
            # shellcheck source=/dev/null
            source "$_bs_candidate"
            (( ${+functions[bs-compile-zsh]} )) || continue
            bs-reset
            local _em_tmp="${_em_cache_file}.tmp.$$"
            bs-compile-zsh "$(< "$_em_scm_file")" > "$_em_tmp"
            mv -f "$_em_tmp" "$_em_cache_file" 2>/dev/null || { rm -f "$_em_tmp"; }
            _em_compiled=1
            break
        done

        if [[ -z "$_em_compiled" ]]; then
            print "em: bs.sh found but bs-compile-zsh missing — update sheme." >&2
            return 1
        fi

        source "$_em_cache_file"
    fi

    # Safety-net trap: restore terminal if killed unexpectedly
    local _em_saved_traps
    _em_saved_traps=$(trap -p INT TERM HUP 2>/dev/null)
    trap 'printf "\e[0m\e[?25h\e[?1049l"; [[ -n "${__bsc_stty_saved:-}" ]] && stty "$__bsc_stty_saved" 2>/dev/null; __bsc_stty_saved=""; trap - INT TERM HUP; return 130' INT
    trap 'printf "\e[0m\e[?25h\e[?1049l"; [[ -n "${__bsc_stty_saved:-}" ]] && stty "$__bsc_stty_saved" 2>/dev/null; __bsc_stty_saved=""; trap - INT TERM HUP; return 143' TERM
    trap 'printf "\e[0m\e[?25h\e[?1049l"; [[ -n "${__bsc_stty_saved:-}" ]] && stty "$__bsc_stty_saved" 2>/dev/null; __bsc_stty_saved=""; trap - INT TERM HUP; return 129' HUP

    # Warn before loading very large files (>= 10MB)
    if [[ -n "${1:-}" && -f "$1" ]]; then
        local _em_fsize
        _em_fsize=$(stat -f%z "$1" 2>/dev/null) || _em_fsize=$(stat --format=%s "$1" 2>/dev/null) || _em_fsize=0
        if (( _em_fsize >= 10485760 )); then
            local _em_mb=$(( _em_fsize / 1048576 ))
            printf "Warning: %s is %d MB.\n" "$1" "$_em_mb" >&2
            printf "Press Enter to continue or Ctrl-C to abort: " >&2
            read -r || { trap - INT TERM HUP; [[ -n "$_em_saved_traps" ]] && eval "$_em_saved_traps"; return 130; }
        fi
    fi

    # Run the editor — em_main is a native zsh function from the compiled cache
    em_main "${1:-}"

    # Restore traps
    trap - INT TERM HUP
    [[ -n "$_em_saved_traps" ]] && eval "$_em_saved_traps"
    return 0
}

# Standalone execution: zsh em.zsh [filename]
if [[ "${(%):-%N}" == "$0" ]]; then
    em "$@"
fi
