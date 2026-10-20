#!/usr/bin/env bash
# =============================================================================
#  flutstaller - Flutter development environment setup for Linux and macOS
#
#  Installs exactly three components, all underneath a single install root
#  (default $HOME/development):
#
#    1. Flutter SDK (current stable)          -> <root>/flutter
#    2. Android SDK command-line tools only   -> <root>/Android/Sdk
#    3. The platform toolchain for Flutter desktop
#       Linux : clang, cmake, ninja, pkg-config, GTK 3 and libstdc++ headers
#       macOS : Xcode, its command line tools and the accepted licences
#
#  Android Studio is never installed. Git, a JDK and editors are never
#  installed unless the operator explicitly opts in.
#
#  Every download URL is resolved at run time from the vendor's own published
#  manifest, so current official artifacts are used and none of them are
#  hard-coded.
#
#  This script was written by an AI coding agent (OpenCode) from a written
#  specification. It is MIT licensed and meant to be read: the whole program is
#  this one file.
# =============================================================================

set -uo pipefail

# -----------------------------------------------------------------------------
# Official vendor endpoints.
#
# FLUTTER_RELEASES_URL is built in detect_platform, because each platform has
# its own release manifest.
# -----------------------------------------------------------------------------
ANDROID_REPO_URL="https://dl.google.com/android/repository/repository2-3.xml"
ANDROID_REPO_BASE="https://dl.google.com/android/repository/"

# -----------------------------------------------------------------------------
# Defaults
# -----------------------------------------------------------------------------
INSTALL_ROOT="${HOME}/development"
DRY_RUN=0
PREFLIGHT_ONLY=0
ASSUME_YES=0
INSTALL_PREREQUISITES=0
SKIP_ANDROID=0
SKIP_ANDROID_LICENSES=0
SKIP_VERIFICATION=0
SKIP_DESKTOP_TOOLCHAIN=0
LOG_DIR=""

# Resolved at run time
FLUTTER_PLATFORM=""     # linux | macos
HOST_OS=""              # linux | macos
HOST_ARCH=""            # x64 | arm64
PKG_MANAGER=""          # apt | dnf | yum | zypper | pacman | apk | xbps | emerge | eopkg | brew
PROFILE_FILE=""
IS_PIPED=0
WORK_DIR=""

# -----------------------------------------------------------------------------
# Output helpers
# -----------------------------------------------------------------------------
if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
    C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'; C_CYAN=$'\033[36m'; C_GREY=$'\033[90m'
else
    C_RESET=""; C_BOLD=""; C_DIM=""
    C_RED=""; C_GREEN=""; C_YELLOW=""
    C_BLUE=""; C_CYAN=""; C_GREY=""
fi

MARK_OK="[+]"; MARK_FAIL="[x]"; MARK_WARN="[!]"; MARK_SKIP="[.]"
if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ]; then
    MARK_OK=$'\033[32m[+]\033[0m'; MARK_FAIL=$'\033[31m[x]\033[0m'
    MARK_WARN=$'\033[33m[!]\033[0m'; MARK_SKIP=$'\033[90m[.]\033[0m'
fi

LOG_FILE=""

log() { printf '%s\n' "$*"; }
log_to_file() { [ -n "$LOG_FILE" ] && printf '%s\n' "$*" >> "$LOG_FILE" 2>/dev/null; return 0; }

info()  { log "$*"; log_to_file "$(date '+%Y-%m-%d %H:%M:%S') [INFO ] $*"; }
ok()    { log "${C_GREEN}$MARK_OK${C_RESET} $*"; log_to_file "$(date '+%Y-%m-%d %H:%M:%S') [OK   ] $*"; }
warn()  { log "${C_YELLOW}$MARK_WARN${C_RESET} $*"; log_to_file "$(date '+%Y-%m-%d %H:%M:%S') [WARN ] $*"; }
fail()  { log "${C_RED}$MARK_FAIL${C_RESET} $*"; log_to_file "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $*"; }
detail(){ log "${C_GREY}    $*${C_RESET}"; log_to_file "$(date '+%Y-%m-%d %H:%M:%S') [DETL ] $*"; }
status(){ log "${C_CYAN}$*${C_RESET}"; log_to_file "$(date '+%Y-%m-%d %H:%M:%S') [STAT] $*"; }

banner() {
    local w=96
    log ""
    log "${C_CYAN}+$(printf '=%.0s' $(seq 1 $((w-2))))+${C_RESET}"
    log "${C_CYAN}|$(printf '%*s' $((w-2)) '')|${C_RESET}"
    log "${C_CYAN}|   ${C_BOLD}flutstaller${C_RESET}   ·   Flutter development environment for ${HOST_OS}${C_RESET}"
    log "${C_CYAN}|   Flutter SDK   ·   Android SDK (command-line tools)   ·   ${HOST_OS} toolchain${C_RESET}"
    log "${C_CYAN}|$(printf '%*s' $((w-2)) '')|${C_RESET}"
    log "${C_CYAN}|   AI-generated with OpenCode - please read the source before running it.${C_RESET}"
    log "${C_CYAN}|$(printf '%*s' $((w-2)) '')|${C_RESET}"
    log "${C_CYAN}+$(printf '=%.0s' $(seq 1 $((w-2))))+${C_RESET}"
}

section() {
    local title="$1"; shift
    local detail="${1:-}"
    log ""
    log "${C_DIM}$(printf -- '-%.0s' $(seq 1 96))${C_RESET}"
    if [ -n "$detail" ]; then
        log "${C_BLUE}  ${C_BOLD}$title${C_RESET}  ${C_DIM}·${C_RESET}  $detail"
    else
        log "${C_BLUE}  ${C_BOLD}$title${C_RESET}"
    fi
    log "${C_DIM}$(printf -- '-%.0s' $(seq 1 96))${C_RESET}"
    log_to_file "$(date '+%Y-%m-%d %H:%M:%S') [SECT ] $title ${detail:+- $detail}"
}

box() {
    local title="$1"; shift
    local w=96 inner=94
    if [ -n "$title" ]; then
        log "${C_DIM}+- ${title} $(printf -- '-%.0s' $(seq 1 $((w - ${#title} - 5))))+${C_RESET}"
    else
        log "${C_DIM}+$(printf -- '-%.0s' $(seq 1 $((w-2))))+${C_RESET}"
    fi
    while IFS= read -r line; do
        local text=" $line"
        # Long lines (URLs) wrap rather than breaking the frame.
        while [ "${#text}" -gt "$inner" ]; do
            log "${C_DIM}|${C_RESET}$(printf '%s' "${text:0:$inner}")${C_DIM}|${C_RESET}"
            text=" ${text:$inner}"
        done
        local pad=$((inner - ${#text}))
        [ "$pad" -lt 0 ] && pad=0
        log "${C_DIM}|${C_RESET}$(printf '%s' "$text")$(printf '%*s' $pad '')${C_DIM}|${C_RESET}"
    done <<< "$*"
    log "${C_DIM}+$(printf -- '-%.0s' $(seq 1 $((w-2))))+${C_RESET}"
}

die() {
    fail "$*"
    exit 1
}

confirm() {
    local prompt="$1" default_no="${2:-0}" answer
    if [ "$ASSUME_YES" -eq 1 ] && [ "$default_no" -eq 0 ]; then
        info "[auto-confirmed] $prompt"
        return 0
    fi
    printf '\n'
    printf '%s  %s %s : ' "${C_YELLOW}->${C_RESET}" "$prompt" "$([ "$default_no" -eq 1 ] && echo '[y/N]' || echo '[Y/n]')"
    read -r answer
    if [ -z "$answer" ]; then
        [ "$default_no" -eq 1 ] && return 1
        return 0
    fi
    case "$answer" in
        y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

# -----------------------------------------------------------------------------
# Small utilities
# -----------------------------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

human_size() {
    local bytes="${1:-0}"
    awk -v b="$bytes" 'BEGIN{
        split("B KB MB GB TB", u, " "); i=1
        while (b >= 1024 && i < 5) { b /= 1024; i++ }
        printf (i==1 ? "%d %s" : "%.1f %s"), b, u[i]
    }'
}

human_duration() {
    local s="${1:-0}"
    [ "$s" -lt 0 ] && echo "--:--"
    local m=$((s / 60)) sec=$((s % 60))
    if [ "$m" -ge 60 ]; then
        printf '%02d:%02d:%02d' $((m / 60)) $((m % 60)) "$sec"
    else
        printf '%02d:%02d' "$m" "$sec"
    fi
}

file_size() {
    if stat -c%s "$1" >/dev/null 2>&1; then stat -c%s "$1" 2>/dev/null || echo 0
    elif stat -f%z "$1" >/dev/null 2>&1; then stat -f%z "$1" 2>/dev/null || echo 0
    else echo 0; fi
}

# -----------------------------------------------------------------------------
# Platform detection
# -----------------------------------------------------------------------------
detect_platform() {
    local os arch
    os="$(uname -s)"
    case "$os" in
        Linux)  HOST_OS="linux"; FLUTTER_PLATFORM="linux" ;;
        Darwin) HOST_OS="macos"; FLUTTER_PLATFORM="macos" ;;
        *) die "Unsupported operating system: $os. This script supports Linux and macOS." ;;
    esac

    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64) HOST_ARCH="x64" ;;
        arm64|aarch64) HOST_ARCH="arm64" ;;
        *) die "Unsupported CPU architecture: $arch" ;;
    esac

    FLUTTER_RELEASES_URL="https://storage.googleapis.com/flutter_infra_release/releases/releases_${FLUTTER_PLATFORM}.json"
    info "Detected $HOST_OS on $HOST_ARCH"
}

detect_package_manager() {
    if [ "$HOST_OS" = "macos" ]; then
        if have brew; then PKG_MANAGER="brew"; else PKG_MANAGER="none"; fi
        return
    fi
    for pm in apt-get dnf yum zypper pacman apk xbps-install emerge eopkg; do
        if have "$pm"; then PKG_MANAGER="$pm"; return; fi
    done
    PKG_MANAGER="none"
}

detect_profile() {
    local shell_name
    shell_name="$(basename "${SHELL:-/bin/sh}")"
    case "$shell_name" in
        zsh)  PROFILE_FILE="$HOME/.zshrc" ;;
        bash) PROFILE_FILE="$HOME/.bashrc" ;;
        fish) PROFILE_FILE="" ;;   # fish uses a different syntax; handled separately
        *)    PROFILE_FILE="$HOME/.profile" ;;
    esac
}

# -----------------------------------------------------------------------------
# Manifest parsing
#
# Everything is parsed with standard shell tools, so the script has no
# dependency beyond curl, tar and unzip. (A python3 or jq install cannot be
# assumed: on some systems python3 is only a stub.)
# -----------------------------------------------------------------------------
resolve_flutter_release() {
    local manifest="$WORK_DIR/flutter-releases.json"
    info "Resolving the current Flutter stable release from the official manifest..."
    if ! download_file "$FLUTTER_RELEASES_URL" "$manifest" ""; then
        die "Could not download the Flutter release manifest from $FLUTTER_RELEASES_URL"
    fi

    # "current_release" holds the hash of the release that is current on each
    # channel. Only the "stable" entry is a 40 character hash.
    local stable_hash
    stable_hash="$(grep -o '"stable": "[a-f0-9]\{40\}"' "$manifest" | head -1 | cut -d'"' -f4)"
    [ -z "$stable_hash" ] && die "Could not read the current stable release from the manifest."

    # The release objects are flat, so the one carrying the stable hash can be
    # pulled out and read field by field.
    local block
    block="$(tr '{' '\n' < "$manifest" | grep -A 20 "\"hash\": \"$stable_hash\"" | head -20)"

    local version archive sha256 base_url
    version="$(printf '%s\n' "$block" | sed -n 's/.*"version": "\([^"]*\)".*/\1/p' | head -1)"
    archive="$(printf '%s\n' "$block" | sed -n 's/.*"archive": "\([^"]*\)".*/\1/p' | head -1)"
    sha256="$(printf '%s\n' "$block" | sed -n 's/.*"sha256": "\([^"]*\)".*/\1/p' | head -1)"
    base_url="$(grep -o '"base_url": "[^"]*"' "$manifest" | head -1 | sed 's/.*"base_url": "//; s/"$//')"
    [ -z "$base_url" ] && base_url="https://storage.googleapis.com/flutter_infra_release/releases"

    [ -z "$archive" ] && die "Could not find the current stable Flutter release in the manifest."

    FLUTTER_VERSION="$version"
    FLUTTER_URL="$base_url/$archive"
    FLUTTER_SHA256="$sha256"
    ok "Flutter stable $version"
    detail "$FLUTTER_URL"
}

resolve_android_cmdline_tools() {
    local manifest="$WORK_DIR/android-repository.xml"
    info "Resolving the Android command-line tools from the official repository manifest..."
    if ! download_file "$ANDROID_REPO_URL" "$manifest" ""; then
        die "Could not download the Android repository manifest from $ANDROID_REPO_URL"
    fi

    # The manifest lists one <remotePackage path="cmdline-tools;latest"> whose
    # <archives> contain one <archive> per host. Only the root element carries
    # a namespace prefix, so the elements are matched by local-name.
    local want_os="windows" want_arch="-"
    if [ "$HOST_OS" = "linux" ]; then
        want_os="linux"; want_arch="-"
    else
        want_os="macosx"
        if [ "$HOST_ARCH" = "arm64" ]; then want_arch="aarch64"; else want_arch="x64"; fi
    fi

    local parsed
    parsed="$(awk -v os="$want_os" -v arch="$want_arch" '
        /<remotePackage path="cmdline-tools;latest">/ { inpkg=1 }
        inpkg && /<\/remotePackage>/ { inpkg=0 }
        inpkg {
            if ($0 ~ /<url>/)      { u=$0; gsub(/^.*<url>/,"",u); gsub(/<\/url>.*/,"",u) }
            if ($0 ~ /<checksum/)   { c=$0; gsub(/^.*<checksum[^>]*>/,"",c); gsub(/<\/checksum>.*/,"",c) }
            if ($0 ~ /<size>/)      { s=$0; gsub(/^.*<size>/,"",s); gsub(/<\/size>.*/,"",s) }
            if ($0 ~ /<host-os>/)   { o=$0; gsub(/^.*<host-os>/,"",o); gsub(/<\/host-os>.*/,"",o) }
            if ($0 ~ /<host-arch>/) { a=$0; gsub(/^.*<host-arch>/,"",a); gsub(/<\/host-arch>.*/,"",a) }
            if ($0 ~ /<\/archive>/) {
                # The archive is only matched once both host-os and host-arch
                # are known. Linux and Windows have no host-arch.
                if (o == os && (arch == "-" || a == arch)) { print u "|" c "|" s; exit }
                u=""; c=""; s=""; o=""; a=""
            }
        }
    ' "$manifest")"

    if [ -z "$parsed" ]; then
        die "No $want_os command-line tools archive found in the Android repository manifest."
    fi
    local url sha1 size
    url="${parsed%%|*}"; parsed="${parsed#*|}"
    sha1="${parsed%%|*}"; size="${parsed##*|}"
    ANDROID_TOOLS_URL="$ANDROID_REPO_BASE$url"
    ANDROID_TOOLS_SHA1="$sha1"
    ok "Android command-line tools resolved ($url, $(human_size "$size"))"
    detail "$ANDROID_TOOLS_URL"
}

resolve_android_packages() {
    # Reads the build-tools and platforms packages out of the same manifest.
    # The manifest uses the legacy "build-tools;37.0.0" form; the Android CLI
    # wants "build-tools/37.0.0", so the separator is converted afterwards.
    # The result is newline separated so that it can be read back safely.
    local manifest="$WORK_DIR/android-repository.xml"

    ANDROID_BUILD_TOOLS="$(awk '
        /<remotePackage path="build-tools;/ {
            path=$0; gsub(/^.*path="/,"",path); gsub(/".*/,"",path)
            if (path ~ /^build-tools;[0-9]+\.[0-9]+\.[0-9]+$/) {
                v = path; sub(/^build-tools;/,"",v)
                split(v, p, ".")
                key = p[1]*1000000 + p[2]*1000 + p[3]
                if (key > m1) { m2=m1; path2=path2; m1=key; path1=path }
                else if (key > m2) { m2=key; path2=path }
            }
        }
        END { if (path2 != "") print path2; if (path1 != "") print path1 }
    ' "$manifest" | tr ';' '/')"

    ANDROID_PLATFORMS="$(awk '
        /<remotePackage path="platforms;android-/ {
            path=$0; gsub(/^.*path="/,"",path); gsub(/".*/,"",path)
            if (path ~ /^platforms;android-[0-9]+$/) {
                v = path; sub(/^platforms;android-/,"",v)
                if (v + 0 > max) { max = v + 0; best = path }
            }
        }
        END { if (best != "") print best }
    ' "$manifest" | tr ';' '/')"
}

# -----------------------------------------------------------------------------
# Download with a live progress bar
# -----------------------------------------------------------------------------
render_progress() {
    # The in-place bar is only drawn to a real terminal; a redirected stream
    # gets a plain line every few seconds instead.
    if [ ! -t 2 ]; then
        if [ "${PROGRESS_LAST_LINE:-0}" -gt 0 ]; then
            printf '\r%*s\r' 100 "" >&2
        fi
        PROGRESS_LAST_LINE=0
        return 0
    fi
    local label="$1" pct="$2" cur="$3" total="$4" speed="$5" eta="$6"
    local w=96 barw=28 filled="" i
    if [ "$total" -gt 0 ]; then
        filled=$(( pct * barw / 100 ))
    else
        filled=0
    fi
    local bar=""
    for ((i = 0; i < filled; i++)); do bar+="#"; done
    for ((i = filled; i < barw; i++)); do bar+="-"; done
    local pct_text="  ---"
    [ "$total" -gt 0 ] && pct_text=$(printf '%5.1f%%' "$pct")
    local size_text
    if [ "$total" -gt 0 ]; then
        size_text="$(human_size "$cur") / $(human_size "$total")"
    else
        size_text="$(human_size "$cur")"
    fi
    local speed_text="       --"
    [ "${speed%.*}" -gt 0 ] 2>/dev/null && speed_text=$(printf '%9s' "$(human_size "$speed")/s")
    local eta_text="--:--"
    [ "$eta" -ge 0 ] 2>/dev/null && eta_text=$(human_duration "$eta")
    local line
    line=$(printf '%s  %-28.28s  [%s] %6s  %-20s %10s  ETA %s' \
        "Downloading" "$label" "$bar" "$pct_text" "$size_text" "$speed_text" "$eta_text")
    printf '\r%s' "$line" >&2
    PROGRESS_LAST_LINE=1
}

download_file() {
    # download_file <url> <destination> [expected-sha256]
    local url="$1" dest="$2" expected="${3:-}"
    local tmp="$dest.part"
    rm -f "$tmp"

    local total=0
    total=$(curl -sIL "$url" 2>/dev/null | awk 'BEGIN{IGNORECASE=1} /^content-length:/ {n=$2} END{gsub(/\r/,"",n); print n+0}')

    if ! have curl; then
        die "curl is required to download files but was not found. Install curl and re-run."
    fi

    local start now cur pct speed eta last_time last_size
    start=$(date +%s); last_time=$start; last_size=0; speed=0

    curl -L --fail --silent --show-error --output "$tmp" "$url" &
    local pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        cur=$(file_size "$tmp")
        now=$(date +%s)
        local dt=$(( now - last_time ))
        if [ "$dt" -ge 1 ]; then
            speed=$(( (cur - last_size) / dt ))
            last_time=$now; last_size=$cur
        fi
        if [ "$total" -gt 0 ]; then
            pct=$(( cur * 100 / total ))
            eta=0
            [ "$speed" -gt 0 ] && eta=$(( (total - cur) / speed ))
        else
            pct=0; eta=-1
        fi
        render_progress "$(basename "$dest")" "$pct" "$cur" "$total" "$speed" "$eta"
        sleep 0.4
    done
    wait "$pid"; local rc=$?
    printf '\r%*s\r' 100 "" >&2

    if [ "$rc" -ne 0 ]; then
        rm -f "$tmp"
        fail "Download failed: $url"
        return 1
    fi
    mv -f "$tmp" "$dest"

    if [ -n "$expected" ]; then
        local actual
        if have sha256sum; then
            actual=$(sha256sum "$dest" | awk '{print $1}')
        elif have shasum; then
            actual=$(shasum -a 256 "$dest" | awk '{print $1}')
        else
            actual=""
        fi
        if [ -n "$actual" ] && [ "$actual" != "$expected" ]; then
            fail "Checksum mismatch for $url"
            detail "expected SHA256 $expected"
            detail "actual   SHA256 $actual"
            rm -f "$dest"
            return 1
        fi
        [ -n "$actual" ] && ok "SHA256 verified: $actual"
    fi
    return 0
}

verify_checksum() {
    # verify_checksum <file> <sha1|sha256> <expected>
    local file="$1" algo="$2" expected="$3"
    [ -z "$expected" ] && return 0
    local actual=""
    case "$algo" in
        sha256)
            if have sha256sum; then actual=$(sha256sum "$file" | awk '{print $1}')
            elif have shasum; then actual=$(shasum -a 256 "$file" | awk '{print $1}')
            fi
            ;;
        sha1)
            if have sha1sum; then actual=$(sha1sum "$file" | awk '{print $1}')
            elif have shasum; then actual=$(shasum -a 1 "$file" | awk '{print $1}')
            fi
            ;;
    esac
    if [ -z "$actual" ]; then
        warn "No $algo tool is available, so the checksum could not be verified."
        return 0
    fi
    if [ "$actual" != "$expected" ]; then
        fail "Checksum mismatch for $file"
        detail "expected $algo $expected"
        detail "actual   $algo $actual"
        return 1
    fi
    ok "$algo verified: $actual"
    return 0
}

# -----------------------------------------------------------------------------
# Environment (shell profile)
# -----------------------------------------------------------------------------
profile_block() {
    local flutter_dir="$1" android_dir="$2" jdk_dir="$3"
    cat <<EOF
# >>> flutstaller >>>
# Added by flutstaller. Managed block - do not edit by hand.
export ANDROID_HOME="$android_dir"
export ANDROID_SDK_ROOT="$android_dir"
EOF
    if [ -n "$jdk_dir" ]; then
        echo "export JAVA_HOME=\"$jdk_dir\""
    fi
    echo "export PATH=\"\$PATH:$flutter_dir/bin\""
    echo "export PATH=\"\$PATH:$android_dir/platform-tools\""
    echo "export PATH=\"\$PATH:$android_dir/cmdline-tools/latest/bin\""
    [ -n "$jdk_dir" ] && echo "export PATH=\"\$PATH:$jdk_dir/bin\""
    echo "# <<< flutstaller <<<"
}

remove_profile_block() {
    local file="$1"
    [ -f "$file" ] || return 0
    local tmp="$file.flutstaller.tmp"
    awk '
        /^# >>> flutstaller >>>$/ { skip=1; next }
        /^# <<< flutstaller <<<$/ { skip=0; next }
        skip { next }
        { print }
    ' "$file" > "$tmp" 2>/dev/null || return 0
    # Drop the blank lines that the removed block left behind.
    sed -i -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}' "$tmp" 2>/dev/null
    mv -f "$tmp" "$file"
    return 0
}

apply_environment() {
    local flutter_dir="$1" android_dir="$2" jdk_dir="$3"
    if [ -z "$PROFILE_FILE" ]; then
        warn "Could not work out which shell profile to update (fish shells use a different syntax)."
        detail "Add these to your shell configuration by hand:"
        detail "  export ANDROID_HOME=\"$android_dir\""
        detail "  export ANDROID_SDK_ROOT=\"$android_dir\""
        detail "  export PATH=\"\$PATH:$flutter_dir/bin:$android_dir/platform-tools:$android_dir/cmdline-tools/latest/bin\""
        return 0
    fi

    remove_profile_block "$PROFILE_FILE"
    {
        printf '\n'
        profile_block "$flutter_dir" "$android_dir" "$jdk_dir"
    } >> "$PROFILE_FILE"
    ok "Updated $PROFILE_FILE"
    detail "PATH, ANDROID_HOME and ANDROID_SDK_ROOT are set for new shells."
    detail "Run: source $PROFILE_FILE   (or open a new terminal)"
}

# -----------------------------------------------------------------------------
# Linux desktop toolchain
# -----------------------------------------------------------------------------
linux_packages() {
    # The packages Flutter's own documentation lists for Linux desktop, mapped
    # onto the package manager of the distribution in use.
    case "$PKG_MANAGER" in
        apt-get)
            echo "clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libglu1-mesa"
            ;;
        dnf|yum)
            echo "clang cmake ninja-build pkgconf-pkg-config gtk3-devel liblzma-devel mesa-libGLU-devel"
            ;;
        zypper)
            echo "clang cmake ninja pkg-config gtk3-devel liblzma-devel libglu1-mesa"
            ;;
        pacman)
            echo "clang cmake ninja pkgconf gtk3 xz glu"
            ;;
        apk)
            echo "clang cmake ninja-build pkgconf gtk3-dev xz-dev mesa-glu-dev"
            ;;
        xbps-install)
            echo "clang cmake ninja pkg-config gtk3-devel liblzma-devel"
            ;;
        emerge)
            echo "dev-util/clang dev-build/cmake dev-build/ninja dev-util/pkgconf x11-libs/gtk+ dev-libs/liblzma"
            ;;
        eopkg)
            echo "clang cmake ninja pkgconf gtk3-devel xz-devel"
            ;;
        *)
            echo ""
            ;;
    esac
}

libstdcxx_package() {
    # The libstdc++ headers are published per GCC major version on Debian and
    # Ubuntu, so the newest one that the distribution actually offers is used.
    case "$PKG_MANAGER" in
        apt-get)
            local cand
            cand="$(apt-cache search --names-only '^libstdc\+\+-[0-9]+-dev$' 2>/dev/null | sort -V | tail -1)"
            [ -n "$cand" ] && echo "$cand" || echo "libstdc++-12-dev"
            ;;
        *)
            echo ""
            ;;
    esac
}

install_linux_toolchain() {
    if [ "$PKG_MANAGER" = "none" ]; then
        warn "No supported package manager was found, so the Linux desktop toolchain was not installed."
        detail "Flutter needs: clang, cmake, ninja, pkg-config, libgtk-3-dev and the libstdc++ headers."
        return 1
    fi

    local pkgs_str; pkgs_str="$(linux_packages)"
    local stdcxx; stdcxx="$(libstdcxx_package)"
    [ -n "$stdcxx" ] && pkgs_str="$pkgs_str $stdcxx"

    # read -a is used rather than mapfile because macOS still ships bash 3.2.
    local -a pkgs=()
    IFS=' ' read -r -a pkgs <<< "$(printf '%s' "$pkgs_str" | tr -s ' ' '\n' | grep -v '^$' | tr '\n' ' ')"

    status "Linux desktop packages: ${pkgs[*]}"

    local -a cmd
    case "$PKG_MANAGER" in
        apt-get)     cmd=(sudo apt-get install -y "${pkgs[@]}") ;;
        dnf)         cmd=(sudo dnf install -y "${pkgs[@]}") ;;
        yum)         cmd=(sudo yum install -y "${pkgs[@]}") ;;
        zypper)      cmd=(sudo zypper install -y "${pkgs[@]}") ;;
        pacman)      cmd=(sudo pacman -S --needed --noconfirm "${pkgs[@]}") ;;
        apk)         cmd=(sudo apk add "${pkgs[@]}") ;;
        xbps-install) cmd=(sudo xbps-install -Sy "${pkgs[@]}") ;;
        emerge)      cmd=(sudo emerge "${pkgs[@]}") ;;
        eopkg)       cmd=(sudo eopkg install "${pkgs[@]}") ;;
        *)           return 1 ;;
    esac

    detail "sudo is used so the packages are installed with the rights they need."
    if ! "${cmd[@]}"; then
        fail "Installing the Linux desktop packages failed."
        return 1
    fi
    ok "Linux desktop toolchain installed"
    return 0
}

# -----------------------------------------------------------------------------
# macOS toolchain (Xcode)
# -----------------------------------------------------------------------------
install_macos_toolchain() {
    if have xcodebuild && [ -n "$(xcode-select -p 2>/dev/null)" ]; then
        ok "Xcode command line tools found at $(xcode-select -p)"
        detail "$(xcodebuild -version 2>/dev/null | tr '\n' ' ')"
    else
        warn "The Xcode command line tools are not installed."
        detail "They are needed to build macOS and iOS apps."
        detail "Installing them now - macOS will show a system dialog for this."
        xcode-select --install 2>/dev/null
        detail "Finish the installation, then re-run this script."
        return 1
    fi

    # Rosetta 2 lets the remaining x86_64 tools run on Apple Silicon.
    if [ "$HOST_ARCH" = "arm64" ] && [ "$HOST_OS" = "macos" ]; then
        if arch -x86_64 /usr/bin/true >/dev/null 2>&1; then
            ok "Rosetta 2 is available"
        else
            warn "Rosetta 2 is not installed; some x86_64 tools will not run."
            detail "Install it with: softwareupdate --install-rosetta --agree-to-license"
            detail "That command accepts a licence, so it is left for you to run."
        fi
    fi

    # The Xcode licence is never accepted without an explicit confirmation.
    if xcodebuild -version >/dev/null 2>&1 && xcodebuild -license check >/dev/null 2>&1; then
        ok "The Xcode licence has been accepted"
    else
        log ""
        log "${C_YELLOW}The Xcode licence agreement has not been accepted yet.${C_RESET}"
        log "  It is an Apple software licence agreement. Read it before you accept it:"
        log "  https://www.apple.com/legal/software-license-terms/"
        if confirm "Accept the Xcode licence agreement on this machine?" 1; then
            if sudo xcodebuild -license accept; then
                ok "The Xcode licence was accepted"
            else
                warn "The Xcode licence could not be accepted. Run: sudo xcodebuild -license"
            fi
        else
            warn "The Xcode licence was not accepted."
            detail "macOS and iOS builds will fail until it is. Run: sudo xcodebuild -license"
        fi
    fi
    return 0
}

# -----------------------------------------------------------------------------
# Component installers
# -----------------------------------------------------------------------------
install_flutter() {
    local flutter_dir="$INSTALL_ROOT/flutter"
    if [ -x "$flutter_dir/bin/flutter" ]; then
        ok "Flutter is already installed at $flutter_dir - leaving it untouched."
        return 0
    fi

    status "Downloading the Flutter SDK..."
    info "Downloading the Flutter SDK..."
    local zip="$WORK_DIR/flutter.tar.xz"
    if ! download_file "$FLUTTER_URL" "$zip" "$FLUTTER_SHA256"; then
        fail "The Flutter SDK download failed."
        return 1
    fi

    local staging="$WORK_DIR/flutter-staging"
    rm -rf "$staging"; mkdir -p "$staging"
    status "Extracting the Flutter SDK..."
    if ! tar -xf "$zip" -C "$staging"; then
        fail "Extracting the Flutter SDK failed."
        return 1
    fi
    if [ ! -x "$staging/flutter/bin/flutter" ]; then
        fail "The Flutter archive did not contain the expected layout."
        return 1
    fi

    mkdir -p "$INSTALL_ROOT"
    rm -rf "$flutter_dir"
    mv "$staging/flutter" "$flutter_dir"
    rm -rf "$staging" "$zip"
    ok "Flutter $FLUTTER_VERSION installed at $flutter_dir"
    return 0
}

install_android_tools() {
    local android_dir="$INSTALL_ROOT/Android/Sdk"
    if [ -x "$android_dir/cmdline-tools/latest/bin/android" ] || [ -x "$android_dir/cmdline-tools/latest/bin/sdkmanager" ]; then
        ok "The Android command-line tools are already installed - leaving them untouched."
        return 0
    fi

    status "Downloading the Android SDK command-line tools..."
    local zip="$WORK_DIR/android-cmdline-tools.zip"
    if ! download_file "$ANDROID_TOOLS_URL" "$zip" ""; then
        fail "The Android SDK command-line tools download failed."
        return 1
    fi
    # The repository manifest publishes a SHA-1 for the archive, so it is
    # verified against exactly what the vendor published.
    if ! verify_checksum "$zip" "sha1" "$ANDROID_TOOLS_SHA1"; then
        rm -f "$zip"
        fail "The Android SDK command-line tools failed the checksum check."
        return 1
    fi

    local staging="$WORK_DIR/android-staging"
    rm -rf "$staging"; mkdir -p "$staging"
    status "Extracting the Android SDK command-line tools..."
    if ! unzip -q -o "$zip" -d "$staging"; then
        fail "Extracting the Android command-line tools failed."
        return 1
    fi
    if [ ! -d "$staging/cmdline-tools" ]; then
        fail "The command-line tools archive had an unexpected layout."
        return 1
    fi

    mkdir -p "$android_dir/cmdline-tools/latest"
    # The archive holds a single cmdline-tools folder; its contents belong in
    # <sdk>/cmdline-tools/latest.
    cp -Rp "$staging/cmdline-tools/." "$android_dir/cmdline-tools/latest/"
    # Zip archives do not carry Unix permissions, so the executables are made
    # executable here.
    chmod +x "$android_dir/cmdline-tools/latest/bin/"* 2>/dev/null
    rm -rf "$staging" "$zip"

    if [ ! -x "$android_dir/cmdline-tools/latest/bin/sdkmanager" ]; then
        fail "sdkmanager was not found after the extraction."
        return 1
    fi
    ok "The Android SDK command-line tools installed at $android_dir"
    return 0
}

android_cli() {
    # The native Android CLI is used when it is available; the deprecated
    # sdkmanager is the fallback.
    local android_dir="$INSTALL_ROOT/Android/Sdk"
    if [ -x "$android_dir/cmdline-tools/latest/bin/android" ]; then
        echo "$android_dir/cmdline-tools/latest/bin/android"
    else
        echo "$android_dir/cmdline-tools/latest/bin/sdkmanager"
    fi
}

install_android_packages() {
    local android_dir="$INSTALL_ROOT/Android/Sdk"
    local java_home="$1"
    local cli; cli="$(android_cli)"

    local compile_sdk="$2"
    local packages=()
    local p

    if [ -x "$android_dir/platform-tools/adb" ]; then
        ok "Android platform-tools are already installed."
    else
        packages+=("platform-tools")
    fi

    # build-tools: the newest stable release and the one matching the API level.
    while IFS= read -r p; do
        [ -z "$p" ] && continue
        local dir="${p#*/}"
        if [ -d "$android_dir/build-tools/$dir" ]; then
            ok "$p is already installed."
        else
            packages+=("$p")
        fi
    done <<< "$ANDROID_BUILD_TOOLS"

    if [ -n "$compile_sdk" ]; then
        local plat="platforms/android-$compile_sdk"
        if [ -d "$android_dir/platforms/android-$compile_sdk" ]; then
            ok "$plat is already installed."
        else
            packages+=("$plat")
        fi
    fi
    while IFS= read -r p; do
        [ -z "$p" ] && continue
        if [ -d "$android_dir/$p" ]; then
            ok "$p is already installed."
        else
            packages+=("$p")
        fi
    done <<< "$ANDROID_PLATFORMS"

    if [ ${#packages[@]} -eq 0 ]; then
        ok "All required Android SDK packages are already installed."
        return 0
    fi
    # The compile SDK is often also the newest published platform, so the list
    # is de-duplicated before it is handed to the CLI.
    local -a unique=()
    local seen q
    for q in "${packages[@]}"; do
        local dup=0
        for seen in "${unique[@]}"; do
            [ "$seen" = "$q" ] && dup=1 && break
        done
        [ "$dup" -eq 0 ] && unique+=("$q")
    done
    packages=("${unique[@]}")

    status "Installing Android SDK packages: ${packages[*]}"
    export JAVA_HOME="$java_home"
    export PATH="$java_home/bin:$PATH"

    local args=()
    if [ "$(basename "$cli")" = "android" ]; then
        # The native Android CLI carries its own Java runtime.
        args=("--sdk=$android_dir" "sdk" "install")
    else
        if [ -z "$java_home" ]; then
            fail "The deprecated sdkmanager needs a JDK, and none was found."
            detail "Install a JDK 17+ and re-run, or use command-line tools 23.0+ which ship the native Android CLI."
            return 1
        fi
        args=()
    fi
    args+=("${packages[@]}")

    if ! "$cli" "${args[@]}"; then
        fail "Installing the Android SDK packages failed."
        return 1
    fi
    ok "Installed: ${packages[*]}"
    return 0
}

accept_android_licenses() {
    local android_dir="$INSTALL_ROOT/Android/Sdk"
    local java_home="$1"
    local sdkmanager="$android_dir/cmdline-tools/latest/bin/sdkmanager"

    log ""
    log "${C_YELLOW}The Android SDK is distributed under the Android Software Development Kit${C_RESET}"
    log "${C_YELLOW}License Agreement. Using the Android SDK means you accept that${C_RESET}"
    log "${C_YELLOW}agreement. The full text is published at:${C_RESET}"
    log "  https://developer.android.com/studio/terms"
    box "LICENCE" "The Android SDK packages are covered by the Android Software Development Kit License Agreement.
Using the Android SDK means you accept that agreement.
Full text: https://developer.android.com/studio/terms"

    if ! confirm "Accept the Android SDK License Agreement on this machine?" 1; then
        warn "The Android SDK License Agreement was not accepted."
        detail "The Android SDK packages were not installed and Android builds will not work."
        return 1
    fi
    ok "The Android SDK License Agreement was accepted."

    if [ -x "$sdkmanager" ]; then
        export JAVA_HOME="$java_home"
        export PATH="$java_home/bin:$PATH"
        if yes | "$sdkmanager" --sdk_root="$android_dir" --licenses >/dev/null 2>&1; then
            ok "The Android SDK licences were recorded."
        else
            detail "The licences may already have been recorded by the Android CLI."
        fi
    fi
    return 0
}

# -----------------------------------------------------------------------------
# Prerequisites
# -----------------------------------------------------------------------------
detect_jdk() {
    local jh="${JAVA_HOME:-}"
    if [ -z "$jh" ] && [ -x /usr/libexec/java_home ]; then
        jh="$(/usr/libexec/java_home 2>/dev/null)"
    fi
    if [ -n "$jh" ] && [ -x "$jh/bin/java" ]; then
        local v
        v="$("$jh/bin/java" -version 2>&1 | head -1 | sed -n 's/.*version "\([0-9]*\).*/\1/p')"
        echo "$jh|${v:-unknown}"
        return 0
    fi
    if have java; then
        local jp v
        jp="$(command -v java)"
        v="$(java -version 2>&1 | head -1 | sed -n 's/.*version "\([0-9]*\).*/\1/p')"
        echo "$(dirname "$(dirname "$jp")")|${v:-unknown}"
        return 0
    fi
    return 1
}

install_git() {
    if have git; then ok "Git is already installed."; return 0; fi
    case "$PKG_MANAGER" in
        apt-get)     sudo apt-get install -y git ;;
        dnf)         sudo dnf install -y git ;;
        yum)         sudo yum install -y git ;;
        zypper)      sudo zypper install -y git ;;
        pacman)      sudo pacman -S --needed --noconfirm git ;;
        apk)         sudo apk add git ;;
        xbps-install) sudo xbps-install -Sy git ;;
        emerge)      sudo emerge dev-vcs/git ;;
        eopkg)       sudo eopkg install git ;;
        brew)        brew install git ;;
        *) warn "No package manager available to install Git."; return 1 ;;
    esac
    have git && { ok "Git installed"; return 0; }
    return 1
}

install_jdk() {
    # A JDK is needed by Gradle to build Android apps. The vendor packages
    # differ per distribution, so the distribution's own package is used.
    case "$PKG_MANAGER" in
        apt-get)     sudo apt-get install -y openjdk-17-jdk-headless ;;
        dnf)         sudo dnf install -y java-17-openjdk-devel ;;
        yum)         sudo yum install -y java-17-openjdk-devel ;;
        zypper)      sudo zypper install -y java-17-openjdk-devel ;;
        pacman)      sudo pacman -S --needed --noconfirm jdk17-openjdk ;;
        apk)         sudo apk add openjdk17-jdk ;;
        xbps-install) sudo xbps-install -Sy openjdk17-jdk ;;
        emerge)      sudo emerge dev-java/openjdk:17 ;;
        eopkg)       sudo eopkg install openjdk17-jdk ;;
        brew)        brew install --cask temurin@17 ;;
        *) warn "No supported package manager was found to install a JDK."; return 1 ;;
    esac
    return 0
}

# -----------------------------------------------------------------------------
# Verification
# -----------------------------------------------------------------------------
verify() {
    local flutter_dir="$INSTALL_ROOT/flutter"
    local android_dir="$INSTALL_ROOT/Android/Sdk"
    local results=()

    section "VERIFICATION"

    if [ -x "$flutter_dir/bin/flutter" ]; then
        info "Running: flutter --version"
        "$flutter_dir/bin/flutter" --version 2>&1 | sed 's/^/    /'
        results+=("${C_GREEN}${MARK_OK}${C_RESET} flutter --version")
    else
        results+=("${C_RED}${MARK_FAIL}${C_RESET} flutter was not found")
    fi

    if [ "$HOST_OS" = "linux" ]; then
        "$flutter_dir/bin/flutter" config --enable-linux-desktop >/dev/null 2>&1 \
            && results+=("${C_GREEN}${MARK_OK}${C_RESET} flutter config --enable-linux-desktop") \
            || results+=("${C_RED}${MARK_FAIL}${C_RESET} flutter config --enable-linux-desktop")
    else
        "$flutter_dir/bin/flutter" config --enable-macos-desktop >/dev/null 2>&1 \
            && results+=("${C_GREEN}${MARK_OK}${C_RESET} flutter config --enable-macos-desktop") \
            || results+=("${C_RED}${MARK_FAIL}${C_RESET} flutter config --enable-macos-desktop")
    fi

    if [ -x "$android_dir/platform-tools/adb" ]; then
        "$android_dir/platform-tools/adb" version 2>&1 | head -3 | sed 's/^/    /'
        results+=("${C_GREEN}${MARK_OK}${C_RESET} adb version")
    else
        results+=("${C_RED}${MARK_FAIL}${C_RESET} adb was not found")
    fi

    if [ "$HOST_OS" = "linux" ]; then
        local tool
        for tool in clang cmake ninja pkg-config; do
            if have "$tool"; then
                results+=("${C_GREEN}${MARK_OK}${C_RESET} $tool present")
            else
                results+=("${C_RED}${MARK_FAIL}${C_RESET} $tool is missing")
            fi
        done
        if have pkg-config && pkg-config --exists gtk+-3.0 2>/dev/null; then
            results+=("${C_GREEN}${MARK_OK}${C_RESET} the GTK 3 development libraries")
        else
            results+=("${C_RED}${MARK_FAIL}${C_RESET} the GTK 3 development libraries are missing")
        fi
    else
        if have xcodebuild; then
            results+=("${C_GREEN}${MARK_OK}${C_RESET} Xcode present")
        else
            results+=("${C_RED}${MARK_FAIL}${C_RESET} Xcode is missing")
        fi
    fi

    if [ -d "$android_dir/licenses" ]; then
        results+=("${C_GREEN}${MARK_OK}${C_RESET} the Android SDK licences are recorded")
    else
        results+=("${C_YELLOW}${MARK_WARN}${C_RESET} no Android SDK licence record was found")
    fi

    if [ "$SKIP_DESKTOP_TOOLCHAIN" -eq 1 ]; then
        results+=("${C_GREY}${MARK_SKIP}${C_RESET} the desktop toolchain was skipped")
    fi
    if [ "$SKIP_ANDROID" -eq 1 ]; then
        results+=("${C_GREY}${MARK_SKIP}${C_RESET} the Android SDK was skipped")
    fi

    section "RESULT"
    box "SUMMARY" "$(printf '%s\n' "${results[@]}")"
    return 0
}

# -----------------------------------------------------------------------------
# Usage
# -----------------------------------------------------------------------------
usage() {
    cat <<EOF
flutstaller - Flutter development environment setup for Linux and macOS

Usage:
  install.sh [options]

Options:
  --install-root <dir>   Install everything under <dir> (default: $HOME/development)
  --dry-run              Resolve versions, print the plan and exit
  --preflight-only       Report the environment and exit (read-only, no network)
  --yes                  Do not ask questions (licences are never auto-accepted)
  --install-prerequisites Also install a missing Git and JDK
  --skip-android         Do not install the Android SDK
  --skip-android-licenses  Do not run the licence step
  --skip-desktop-toolchain  Do not install the ${HOST_OS} build toolchain
  --skip-verification    Do not run the final checks
  --log-dir <dir>        Where to write the run log (default: <script dir>/logs)
  -h, --help             Show this help

Environment variables (used by 'curl ... | bash'):
  FLUTSTALLER_INSTALL_ROOT, FLUTSTALLER_INSTALL_PREREQUISITES,
  FLUTSTALLER_SKIP_ANDROID, FLUTSTALLER_SKIP_ANDROID_LICENSES,
  FLUTSTALLER_SKIP_VERIFICATION, FLUTSTALLER_DRY_RUN,
  FLUTSTALLER_PREFLIGHT_ONLY, FLUTSTALLER_YES, FLUTSTALLER_LOG_DIRECTORY

This script was written by an AI coding agent (OpenCode). Please read it
before running it: https://github.com/kernelk14/flutstaller
EOF
}

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --install-root) INSTALL_ROOT="$2"; shift 2 ;;
        --install-root=*) INSTALL_ROOT="${1#*=}"; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --preflight-only) PREFLIGHT_ONLY=1; shift ;;
        --yes|-y) ASSUME_YES=1; shift ;;
        --install-prerequisites) INSTALL_PREREQUISITES=1; shift ;;
        --skip-android) SKIP_ANDROID=1; shift ;;
        --skip-android-licenses) SKIP_ANDROID_LICENSES=1; shift ;;
        --skip-desktop-toolchain) SKIP_DESKTOP_TOOLCHAIN=1; shift ;;
        --skip-verification) SKIP_VERIFICATION=1; shift ;;
        --log-dir) LOG_DIR="$2"; shift 2 ;;
        --log-dir=*) LOG_DIR="${1#*=}"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n\n' "$1" >&2; usage; exit 2 ;;
    esac
done

# Environment variables win when the matching switch was not given.
[ -n "${FLUTSTALLER_INSTALL_ROOT:-}" ] && INSTALL_ROOT="$FLUTSTALLER_INSTALL_ROOT"
[ "${FLUTSTALLER_INSTALL_PREREQUISITES:-0}" = "1" ] && INSTALL_PREREQUISITES=1
[ "${FLUTSTALLER_SKIP_ANDROID:-0}" = "1" ] && SKIP_ANDROID=1
[ "${FLUTSTALLER_SKIP_ANDROID_LICENSES:-0}" = "1" ] && SKIP_ANDROID_LICENSES=1
[ "${FLUTSTALLER_SKIP_VERIFICATION:-0}" = "1" ] && SKIP_VERIFICATION=1
[ "${FLUTSTALLER_DRY_RUN:-0}" = "1" ] && DRY_RUN=1
[ "${FLUTSTALLER_PREFLIGHT_ONLY:-0}" = "1" ] && PREFLIGHT_ONLY=1
[ "${FLUTSTALLER_YES:-0}" = "1" ] && ASSUME_YES=1
[ -n "${FLUTSTALLER_LOG_DIRECTORY:-}" ] && LOG_DIR="$FLUTSTALLER_LOG_DIRECTORY"

# -----------------------------------------------------------------------------
# Start
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
if [ -z "$SCRIPT_DIR" ] || [ "$SCRIPT_DIR" = "." ]; then
    # Piped into bash: there is no script file, so there is no folder either.
    SCRIPT_DIR=""
    IS_PIPED=1
fi
case "${0:-}" in
    bash|sh|dash) IS_PIPED=1 ;;
esac

if [ -z "$LOG_DIR" ]; then
    if [ -n "$SCRIPT_DIR" ] && [ "$IS_PIPED" -eq 0 ]; then
        LOG_DIR="$SCRIPT_DIR/logs"
    else
        LOG_DIR="${TMPDIR:-/tmp}/flutstaller-logs"
    fi
fi
mkdir -p "$LOG_DIR" 2>/dev/null || LOG_DIR="${TMPDIR:-/tmp}"
LOG_FILE="$LOG_DIR/flutter-setup-$(date '+%Y%m%d-%H%M%S').log"
: > "$LOG_FILE" 2>/dev/null || LOG_FILE=""

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/flutstaller-XXXXXX")"
# shellcheck disable=SC2329  # called through the trap below
cleanup() { [ -n "$WORK_DIR" ] && rm -rf "$WORK_DIR"; }
trap cleanup EXIT INT TERM

detect_platform
banner
info "Log file: $LOG_FILE"
info "Install root: $INSTALL_ROOT"
info "This script was written by an AI (OpenCode). Please read the source before running it."

detect_package_manager
detect_profile
[ "$HOST_OS" = "linux" ] && info "Package manager: $PKG_MANAGER"
[ "$HOST_OS" = "macos" ] && info "Homebrew: $(have brew && echo present || echo 'not installed')"

# -----------------------------------------------------------------------------
# Preflight
# -----------------------------------------------------------------------------
if [ "$PREFLIGHT_ONLY" -eq 1 ]; then
    section "PREFLIGHT" "read-only environment report"
    box "PLATFORM" "Operating system ....... $HOST_OS
CPU architecture ...... $HOST_ARCH
Package manager ....... $PKG_MANAGER
Shell ................ ${SHELL:-unknown}
Shell profile ........ ${PROFILE_FILE:-'(could not be determined)'}
Flutter SDK ........... $([ -x "$INSTALL_ROOT/flutter/bin/flutter" ] && echo "installed at $INSTALL_ROOT/flutter" || echo 'not present')
Android SDK .......... $([ -d "$INSTALL_ROOT/Android/Sdk" ] && echo "installed at $INSTALL_ROOT/Android/Sdk" || echo 'not present')"

    jdk_info="$(detect_jdk || true)"
    if [ -n "$jdk_info" ]; then
        box "PREREQUISITES" "Git ................. $(have git && git --version | head -1 || echo 'NOT FOUND')
JDK ................. ${jdk_info#*|}"
    else
        box "PREREQUISITES" "Git ................. $(have git && git --version | head -1 || echo 'NOT FOUND')
JDK ................. NOT FOUND"
    fi

    if [ "$HOST_OS" = "macos" ]; then
        box "XCODE" "xcode-select ....... $(xcode-select -p 2>/dev/null || echo 'NOT INSTALLED')
Xcode version ....... $(xcodebuild -version 2>/dev/null | tr '\n' ' ' || echo 'NOT INSTALLED')"
    fi
    log ""
    ok "Preflight complete - nothing was changed and no download was started."
    exit 0
fi

# -----------------------------------------------------------------------------
# Resolve the vendor manifests
# -----------------------------------------------------------------------------
section "RESOLVING" "official vendor manifests"
resolve_flutter_release
if [ "$SKIP_ANDROID" -eq 0 ]; then
    resolve_android_cmdline_tools
    resolve_android_packages
    info "Newest published stable build-tools: $(printf '%s' "$ANDROID_BUILD_TOOLS" | tr '\n' ',')"
    info "Newest published stable platforms : $(printf '%s' "$ANDROID_PLATFORMS" | tr '\n' ',')"
fi

# -----------------------------------------------------------------------------
# Prerequisites
# -----------------------------------------------------------------------------
section "PREREQUISITES" "Git, JDK"
JDK_PATH=""
if detect_jdk >/dev/null 2>&1; then
    jdk_info="$(detect_jdk)"
    JDK_PATH="${jdk_info%%|*}"
    ok "JDK found (Java ${jdk_info#*|}) at $JDK_PATH"
else
    warn "No JDK (Java 17 or newer) was found."
    detail "Gradle needs one to build Android apps."
    detail "It is installed from your distribution's own repository."
    if [ "$INSTALL_PREREQUISITES" -eq 1 ]; then
        info "Installing a JDK from the distribution's own repository..."
        if install_jdk; then
            jdk_info="$(detect_jdk || true)"
            JDK_PATH="${jdk_info%%|*}"
            ok "JDK installed: $JDK_PATH"
        else
            fail "The JDK could not be installed."
        fi
    elif [ "$ASSUME_YES" -eq 0 ]; then
        box "PREREQUISITES" "Git ................... $(have git && git --version | head -1 || echo 'not installed')
A JDK 17 or newer ... NOT FOUND
The JDK is not part of the components this script installs, so it is only
installed if you ask for it."
        if confirm "Install the missing prerequisites (a JDK) now?" 1; then
            if install_jdk; then
                jdk_info="$(detect_jdk || true)"
                JDK_PATH="${jdk_info%%|*}"
                ok "JDK installed: $JDK_PATH"
            else
                fail "The JDK could not be installed."
            fi
        else
            warn "The JDK was not installed. Android builds will not work without one."
        fi
    fi
fi

if have git; then
    ok "Git found: $(git --version | head -1)"
elif [ "$INSTALL_PREREQUISITES" -eq 1 ]; then
    install_git && ok "Git installed"
else
    warn "Git was not found. The flutter command needs it."
    detail "Install it with your distribution's package manager."
fi

# -----------------------------------------------------------------------------
# Plan
# -----------------------------------------------------------------------------
section "PLAN" "what is going to change"
plan="Install root ............. $INSTALL_ROOT
Flutter SDK ............... $INSTALL_ROOT/flutter  (stable $FLUTTER_VERSION)"
if [ "$SKIP_ANDROID" -eq 0 ]; then
    plan="$plan
Android SDK .............. $INSTALL_ROOT/Android/Sdk
  cmd-line tools ........ $ANDROID_TOOLS_URL
  packages .............. platform-tools, build-tools, platforms/android-<Flutter compileSdk>"
else
    plan="$plan
Android SDK .............. SKIPPED"
fi
if [ "$HOST_OS" = "linux" ]; then
    plan="$plan
Linux toolchain .......... clang cmake ninja pkg-config GTK 3 and the libstdc++ headers"
else
    plan="$plan
macOS toolchain .......... Xcode, its command line tools and the accepted licences"
fi
plan="$plan

User environment variables that will be set:
  ANDROID_HOME ............ $INSTALL_ROOT/Android/Sdk
  ANDROID_SDK_ROOT ....... $INSTALL_ROOT/Android/Sdk
User PATH entries that will be added (duplicates are skipped):
  $INSTALL_ROOT/flutter/bin
  $INSTALL_ROOT/Android/Sdk/platform-tools
  $INSTALL_ROOT/Android/Sdk/cmdline-tools/latest/bin

Approximate disk requirement: ~8 GB free (Flutter ~3.5 GB, Android SDK ~2 GB, toolchain ~2 GB)."
box "PLAN" "$plan"

if [ "$DRY_RUN" -eq 1 ]; then
    log ""
    ok "DRY RUN complete - nothing was changed."
    exit 0
fi

if ! confirm "Proceed with the installation described above?" 1; then
    log ""
    ok "Cancelled - nothing was changed."
    exit 0
fi

mkdir -p "$INSTALL_ROOT"

# -----------------------------------------------------------------------------
# Install
# -----------------------------------------------------------------------------
section "STEP 1/4" "Flutter SDK"
if ! install_flutter; then
    fail "The Flutter SDK could not be installed."
fi

section "STEP 2/4" "Android SDK command-line tools"
if [ "$SKIP_ANDROID" -eq 0 ]; then
    if ! install_android_tools; then
        fail "The Android command-line tools could not be installed."
    fi
else
    warn "The Android SDK was skipped."
fi

section "STEP 3/4" "$HOST_OS toolchain"
if [ "$SKIP_DESKTOP_TOOLCHAIN" -eq 1 ]; then
    warn "The desktop toolchain was skipped (-SkipDesktopToolchain)."
elif [ "$HOST_OS" = "linux" ]; then
    install_linux_toolchain || warn "The Linux desktop toolchain is not fully installed."
else
    install_macos_toolchain || warn "The macOS toolchain is not fully configured."
fi

section "STEP 4/4" "Android SDK packages"
if [ "$SKIP_ANDROID" -eq 0 ]; then
    # The platform Flutter itself declares as its compile SDK.
    compile_sdk=""
    if [ -f "$INSTALL_ROOT/flutter/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt" ]; then
        compile_sdk="$(sed -n 's/.*compileSdkVersion: *Int *= *\([0-9]*\).*/\1/p' \
            "$INSTALL_ROOT/flutter/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt" | head -1)"
    fi
    if [ -n "$compile_sdk" ]; then
        info "Flutter declares compileSdkVersion = $compile_sdk, so that platform will be installed."
    fi

    licence_ok=0
    if [ "$SKIP_ANDROID_LICENSES" -eq 1 ]; then
        warn "The Android SDK licence step was skipped."
    else
        accept_android_licenses "${JDK_PATH:-}" && licence_ok=1
    fi

    if [ "$licence_ok" -eq 1 ]; then
        install_android_packages "${JDK_PATH:-}" "$compile_sdk" || fail "The Android SDK packages could not be installed."
    else
        warn "The Android SDK packages were not installed because the licence was not accepted."
    fi
fi

# -----------------------------------------------------------------------------
# Environment
# -----------------------------------------------------------------------------
section "ENVIRONMENT" "user PATH, ANDROID_HOME, ANDROID_SDK_ROOT"
apply_environment "$INSTALL_ROOT/flutter" "$INSTALL_ROOT/Android/Sdk" "$JDK_PATH"

# -----------------------------------------------------------------------------
# Flutter configuration
# -----------------------------------------------------------------------------
if [ -x "$INSTALL_ROOT/flutter/bin/flutter" ]; then
    export PATH="$INSTALL_ROOT/flutter/bin:$PATH"
    info "Running: flutter config --android-sdk"
    "$INSTALL_ROOT/flutter/bin/flutter" config --android-sdk "$INSTALL_ROOT/Android/Sdk" 2>&1 | sed 's/^/    /'
    if [ -n "$JDK_PATH" ]; then
        info "Running: flutter config --jdk-dir"
        "$INSTALL_ROOT/flutter/bin/flutter" config --jdk-dir "$JDK_PATH" 2>&1 | sed 's/^/    /'
    fi
fi

# -----------------------------------------------------------------------------
# Verification
# -----------------------------------------------------------------------------
if [ "$SKIP_VERIFICATION" -eq 0 ]; then
    verify
else
    warn "Verification was skipped (-SkipVerification)."
fi

section "RESULT"
log "  Open a NEW terminal before using flutter / adb so the updated PATH is picked up."
log ""
ok "Done. The log file is $LOG_FILE"
exit 0
