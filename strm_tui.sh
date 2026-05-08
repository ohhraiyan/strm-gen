#!/usr/bin/env bash
# strm_tui.sh - FTP → Jellyfin STRM Generator

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_SCRIPT="$SCRIPT_DIR/ftp_to_strm.py"
VENV="$HOME/strm-env"
TMDB_KEY_FILE="$HOME/.strm_tmdb_key"

# ─── Colors & Styles ──────────────────────────────────────────────────────────
R='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
ITALIC='\033[3m'

BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'

BRED='\033[1;31m'
BGREEN='\033[1;32m'
BYELLOW='\033[1;33m'
BBLUE='\033[1;34m'
BMAGENTA='\033[1;35m'
BCYAN='\033[1;36m'
BWHITE='\033[1;37m'

BG_BLACK='\033[40m'
BG_BLUE='\033[44m'
BG_MAGENTA='\033[45m'
BG_CYAN='\033[46m'

# ─── Terminal width ───────────────────────────────────────────────────────────
TW=$(tput cols 2>/dev/null || echo 80)
pad() { printf "%*s" $(( (TW - ${#1}) / 2 )) ""; echo -e "$1"; }
lpad() { printf "    "; echo -e "$1"; }

# ─── UI Primitives ────────────────────────────────────────────────────────────
clear_screen() { clear; }

top_bar() {
    echo ""
    echo -e "${BMAGENTA}$(printf '▀%.0s' $(seq 1 $TW))${R}"
}

bot_bar() {
    echo -e "${BBLUE}$(printf '▄%.0s' $(seq 1 $TW))${R}"
    echo ""
}

divider() {
    lpad "${DIM}${CYAN}$(printf '·%.0s' $(seq 1 $(( TW - 8 ))))${R}"
}

header() {
    top_bar
    echo ""
    pad "${BMAGENTA}░▒▓  ${BCYAN}FTP ${BWHITE}→ ${BMAGENTA}Jellyfin ${BCYAN}STRM ${BWHITE}Generator  ${BMAGENTA}▓▒░${R}"
    pad "${DIM}${CYAN}stream anything, anywhere${R}"
    echo ""
    bot_bar
}

step_header() {
    local step="$1" total="$2" title="$3"
    echo ""
    lpad "${BG_BLACK}${BOLD}${BMAGENTA}  ◈ ${BCYAN}Step ${step}${DIM}/${total}  ${BWHITE}${title}  ${R}"
    echo ""
    divider
    echo ""
}

tag_ok()   { lpad "${BGREEN}  ✦ ${BWHITE}$1${R}"; }
tag_err()  { lpad "${BRED}  ✖ ${BWHITE}$1${R}"; }
tag_info() { lpad "${BCYAN}  ◆ ${WHITE}$1${R}"; }
tag_warn() { lpad "${BYELLOW}  ◈ ${WHITE}$1${R}"; }
tag_run()  { lpad "${BMAGENTA}  ▶ ${WHITE}$1${R}"; }

ask() {
    echo -ne "    ${BMAGENTA}  ❯ ${BCYAN}$1 ${BYELLOW}"; read -r "$2"; echo -ne "${R}"
}

pick() {
    echo -ne "    ${BMAGENTA}  ❯ ${BCYAN}$1 ${BYELLOW}[${2}]${BCYAN}: ${BYELLOW}"; read -r "$3"; echo -ne "${R}"
}

spinner() {
    local pid=$1 msg="$2"
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r    ${BMAGENTA}  %s ${CYAN}%s${R}   " "${frames[$((i % 10))]}" "$msg"
        i=$((i+1)); sleep 0.08
    done
    printf "\r%*s\r" "$TW" ""
}

# ─── Venv bootstrap ───────────────────────────────────────────────────────────
bootstrap_venv() {
    if [[ ! -d "$VENV" ]]; then
        tag_warn "Virtual environment not found. Creating it..."
        echo ""
        python3 -m venv "$VENV" &
        spinner $! "Creating venv..."
        wait $!
        tag_ok "Venv created at $VENV"
    fi

    source "$VENV/bin/activate"

    # Check for required packages
    if ! "$VENV/bin/python" -c "import requests, bs4" 2>/dev/null; then
        tag_warn "Installing dependencies..."
        echo ""
        "$VENV/bin/pip" install -q requests beautifulsoup4 &
        spinner $! "Installing requests & beautifulsoup4..."
        wait $!
        tag_ok "Dependencies installed."
    fi

    PYTHON="$VENV/bin/python"
}

check_deps() {
    if [[ ! -f "$PYTHON_SCRIPT" ]]; then
        tag_err "ftp_to_strm.py not found at: $PYTHON_SCRIPT"
        tag_err "Place ftp_to_strm.py in the same folder as this script."
        echo ""; exit 1
    fi
    bootstrap_venv
}

# ─── Step 1: URL ──────────────────────────────────────────────────────────────
get_url() {
    clear_screen; header
    step_header 1 4 "FTP Index URL"
    tag_info "Paste the HTTP directory URL from the FTP server."
    tag_info "Example: ${DIM}http://172.16.50.14/DHAKA-FLIX-14/English%20Movies%20%281080p%29/${R}"
    echo ""
    ask "URL:" FTP_URL

    if [[ -z "$FTP_URL" ]]; then
        tag_err "URL cannot be empty."; sleep 1.2; get_url; return
    fi
    if [[ ! "$FTP_URL" =~ ^https?:// ]]; then
        tag_err "Must start with http:// or https://"; sleep 1.2; get_url; return
    fi
    echo ""
    tag_ok "URL accepted."
    sleep 0.5
}

# ─── Step 2: Output folder ────────────────────────────────────────────────────
get_output() {
    clear_screen; header
    step_header 2 4 "Output Folder"
    tag_info "Where should the .strm files be saved?"
    echo ""

    local i=1
    declare -ga DIR_OPTIONS=()
    while IFS= read -r dir; do
        lpad "    ${BCYAN}[${BYELLOW}${i}${BCYAN}]${R}  ${WHITE}${dir}${R}"
        DIR_OPTIONS+=("$dir")
        ((i++))
    done < <(find "$HOME" -maxdepth 2 -type d \
        ! -path '*/\.*' ! -path '*/strm-env/*' ! -path '*/node_modules/*' \
        2>/dev/null | sort | head -12)

    echo ""
    lpad "    ${BCYAN}[${BYELLOW}n${BCYAN}]${R}  ${DIM}Enter a custom or new path${R}"
    echo ""
    pick "Select" "1-${#DIR_OPTIONS[@]} or n" CHOICE

    if [[ "$CHOICE" == "n" || "$CHOICE" == "N" ]]; then
        echo ""; ask "Full path:" OUTPUT_DIR
        OUTPUT_DIR="${OUTPUT_DIR/#\~/$HOME}"
        [[ -z "$OUTPUT_DIR" ]] && { tag_err "Path cannot be empty."; sleep 1.2; get_output; return; }
    elif [[ "$CHOICE" =~ ^[0-9]+$ ]] && (( CHOICE >= 1 && CHOICE <= ${#DIR_OPTIONS[@]} )); then
        OUTPUT_DIR="${DIR_OPTIONS[$((CHOICE-1))]}"
    else
        tag_err "Invalid choice."; sleep 1.2; get_output; return
    fi

    if [[ ! -d "$OUTPUT_DIR" ]]; then
        mkdir -p "$OUTPUT_DIR" 2>/dev/null \
            && tag_ok "Created: ${CYAN}$OUTPUT_DIR${R}" \
            || { tag_err "Could not create folder."; sleep 1.2; get_output; return; }
    else
        tag_ok "Output: ${CYAN}$OUTPUT_DIR${R}"
    fi
    sleep 0.5
}

# ─── Step 3: TMDB key ─────────────────────────────────────────────────────────
get_tmdb_key() {
    clear_screen; header
    step_header 3 4 "TMDB API Key"
    tag_info "TMDB gives you clean, properly-capitalised movie titles."
    tag_info "Free key: ${BCYAN}https://www.themoviedb.org/settings/api${R}"
    echo ""

    SAVED_KEY=""
    [[ -f "$TMDB_KEY_FILE" ]] && SAVED_KEY=$(cat "$TMDB_KEY_FILE")

    if [[ -n "$SAVED_KEY" ]]; then
        tag_ok "Saved key found: ${DIM}${SAVED_KEY:0:8}…${R}"
        echo ""
        lpad "    ${BCYAN}[${BYELLOW}1${BCYAN}]${R}  Use saved key"
        lpad "    ${BCYAN}[${BYELLOW}2${BCYAN}]${R}  Enter a new key"
        lpad "    ${BCYAN}[${BYELLOW}3${BCYAN}]${R}  Skip (local extraction)"
        echo ""
        pick "Choice" "1" KC; KC="${KC:-1}"
        case "$KC" in
            1) TMDB_KEY="$SAVED_KEY"; tag_ok "Using saved key." ;;
            2) echo ""; ask "New API key:" TMDB_KEY
               echo "$TMDB_KEY" > "$TMDB_KEY_FILE"; tag_ok "Key saved." ;;
            3) TMDB_KEY=""; tag_warn "Skipping TMDB. Local extraction only." ;;
            *) TMDB_KEY="$SAVED_KEY"; tag_ok "Using saved key." ;;
        esac
    else
        lpad "    ${BCYAN}[${BYELLOW}1${BCYAN}]${R}  Enter TMDB API key"
        lpad "    ${BCYAN}[${BYELLOW}2${BCYAN}]${R}  Skip (local extraction)"
        echo ""
        pick "Choice" "2" KC; KC="${KC:-2}"
        case "$KC" in
            1) echo ""; ask "API key:" TMDB_KEY
               echo "$TMDB_KEY" > "$TMDB_KEY_FILE"; tag_ok "Key saved." ;;
            *) TMDB_KEY=""; tag_warn "Skipping TMDB. Local extraction only." ;;
        esac
    fi
    sleep 0.5
}

# ─── Step 4: Options ──────────────────────────────────────────────────────────
get_options() {
    clear_screen; header
    step_header 4 4 "Options"
    tag_info "Max subfolder depth. This FTP uses ${BCYAN}year → movie${R} folders."
    tag_info "Depth ${BYELLOW}4${R} is recommended."
    echo ""
    pick "Depth" "4" DEPTH; DEPTH="${DEPTH:-4}"
    if [[ ! "$DEPTH" =~ ^[0-9]+$ ]]; then
        tag_err "Must be a number."; sleep 1.2; get_options; return
    fi
    echo ""
    tag_ok "Depth set to ${CYAN}$DEPTH${R}"
    sleep 0.5
}

# ─── Confirm & Run ────────────────────────────────────────────────────────────
confirm_and_run() {
    clear_screen; header
    echo ""
    pad "${BOLD}${BWHITE}◈◈  Ready to Launch  ◈◈${R}"
    echo ""
    divider; echo ""

    lpad "  ${DIM}URL    ${R}  ${CYAN}$FTP_URL${R}"
    lpad "  ${DIM}Output ${R}  ${CYAN}$OUTPUT_DIR${R}"
    if [[ -n "$TMDB_KEY" ]]; then
        lpad "  ${DIM}TMDB   ${R}  ${BGREEN}enabled ${DIM}(${TMDB_KEY:0:8}…)${R}"
    else
        lpad "  ${DIM}TMDB   ${R}  ${BYELLOW}disabled${R}"
    fi
    lpad "  ${DIM}Depth  ${R}  ${CYAN}$DEPTH${R}"
    echo ""
    divider; echo ""

    pick "Start?" "Y/n" CONFIRM
    [[ "$CONFIRM" =~ ^[Nn]$ ]] && { tag_info "Cancelled."; echo ""; exit 0; }

    echo ""
    top_bar
    echo ""
    tag_run "Crawling FTP index..."
    echo ""

    CMD=("$PYTHON" "$PYTHON_SCRIPT" --url "$FTP_URL" --output "$OUTPUT_DIR" --depth "$DEPTH")
    [[ -n "$TMDB_KEY" ]] && CMD+=(--tmdb-key "$TMDB_KEY")
    "${CMD[@]}"
    EXIT_CODE=$?

    echo ""
    bot_bar

    if [[ $EXIT_CODE -eq 0 ]]; then
        echo ""
        pad "${BGREEN}${BOLD}✦  All done!${R}"
        pad "${DIM}${WHITE}Files saved to: ${CYAN}$OUTPUT_DIR${R}"
        echo ""
    else
        echo ""
        pad "${BRED}${BOLD}✖  Something went wrong.${R}"
        pad "${DIM}Check the output above for details.${R}"
        echo ""
    fi

    divider; echo ""
    pick "Run again?" "y/N" AGAIN
    [[ "$AGAIN" =~ ^[Yy]$ ]] && { FTP_URL=""; OUTPUT_DIR=""; TMDB_KEY=""; DEPTH=""; main; }
    echo ""
    pad "${BMAGENTA}${BOLD}◈  See you next time  ◈${R}"
    echo ""
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    check_deps
    get_url
    get_output
    get_tmdb_key
    get_options
    confirm_and_run
}

main
