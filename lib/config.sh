#!/usr/bin/env bash
# =============================================================================
# lib/config.sh — Configuration & Constants
# All user-configurable settings live here. Edit this file to match your setup.
# =============================================================================

# ── Unraid server media paths ─────────────────────────────────────────────────
# Update MEDIA_BASE_PATH to wherever your Torrents share is mounted.
# Common setups:
#   NFS mount  → /mnt/unraid/Torrents
#   SMB mount  → /mnt/smb/Torrents
#   Local disk → /mnt/user/Torrents   (if running this script on the Unraid box)

MEDIA_BASE_PATH="${IA_MEDIA_PATH:-/mnt/user/Torrents}"
MOVIES_PATH="$MEDIA_BASE_PATH/Movies"
TELEVISION_PATH="$MEDIA_BASE_PATH/Television"

# ── Script internal paths ─────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUEUE_DIR="$SCRIPT_DIR/queue"
LOG_DIR="$SCRIPT_DIR/logs"
TEMPLATE_DIR="$SCRIPT_DIR/templates"

# ── Internet Archive settings ─────────────────────────────────────────────────
# Your IA collection. Use "opensource" unless you have a dedicated collection.
IA_DEFAULT_COLLECTION="opensource"

# Mediatype for video files
IA_MOVIE_MEDIATYPE="movies"
IA_TV_MEDIATYPE="movies"

# Publisher tag added to every upload
IA_PUBLISHER="Archived Television and Film Collection"

# Default subject tags always included (add your own)
IA_DEFAULT_SUBJECTS=("archived" "video" "personal-archive")

# Identifier prefix — all items get this prefix for easy searching on IA
IA_IDENTIFIER_PREFIX="archive-media"

# Retry settings for upload
IA_RETRIES=3
IA_RETRIES_SLEEP=10    # seconds between retries

# Checksum verification (slower but safer)
IA_VERIFY_CHECKSUM=true

# ── Video file extensions to recognize ───────────────────────────────────────
# Files with these extensions will be listed as uploadable media.
# Add/remove as needed.
VIDEO_EXTENSIONS=(
    "mkv" "mp4" "avi" "m4v" "mov" "wmv" "flv" "webm"
    "mpg" "mpeg" "ts" "m2ts" "divx" "xvid" "ogv" "rmvb"
)

# ── Subtitle/extra file extensions ───────────────────────────────────────────
# These will be uploaded alongside the main video if present.
EXTRA_EXTENSIONS=(
    "srt" "sub" "idx" "ass" "ssa" "vtt" "nfo" "jpg" "png" "json"
)

# ── Upload queue filename convention ─────────────────────────────────────────
MOVIES_QUEUE_FILE="$QUEUE_DIR/movies_queue.csv"
TV_QUEUE_FILE="$QUEUE_DIR/tv_queue.csv"

# ── UI / display settings ─────────────────────────────────────────────────────
# Terminal width for dividers (auto-detects, falls back to 72)
TERM_WIDTH="${COLUMNS:-72}"
if (( TERM_WIDTH > 100 )); then TERM_WIDTH=100; fi

# Page size for file browser (items shown per screen)
BROWSER_PAGE_SIZE=20

# ── ANSI color codes ──────────────────────────────────────────────────────────
# Disable by setting NO_COLOR=1 in your environment
if [[ -z "${NO_COLOR:-}" ]] && [[ -t 1 ]]; then
    COLOR_RESET="\033[0m"
    COLOR_BOLD="\033[1m"
    COLOR_DIM="\033[2m"
    COLOR_RED="\033[31m"
    COLOR_GREEN="\033[32m"
    COLOR_YELLOW="\033[33m"
    COLOR_CYAN="\033[36m"
    COLOR_BLUE="\033[34m"
    COLOR_MAGENTA="\033[35m"
    COLOR_WHITE="\033[37m"
    COLOR_BG_DARK="\033[40m"
    COLOR_BOLD_GREEN="\033[1;32m"
    COLOR_BOLD_CYAN="\033[1;36m"
    COLOR_BOLD_RED="\033[1;31m"
    COLOR_BOLD_YELLOW="\033[1;33m"
else
    COLOR_RESET=""
    COLOR_BOLD=""
    COLOR_DIM=""
    COLOR_RED=""
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_CYAN=""
    COLOR_BLUE=""
    COLOR_MAGENTA=""
    COLOR_WHITE=""
    COLOR_BG_DARK=""
    COLOR_BOLD_GREEN=""
    COLOR_BOLD_CYAN=""
    COLOR_BOLD_RED=""
    COLOR_BOLD_YELLOW=""
fi

export COLOR_RESET COLOR_BOLD COLOR_DIM COLOR_RED COLOR_GREEN COLOR_YELLOW
export COLOR_CYAN COLOR_BLUE COLOR_MAGENTA COLOR_WHITE COLOR_BG_DARK
export COLOR_BOLD_GREEN COLOR_BOLD_CYAN COLOR_BOLD_RED COLOR_BOLD_YELLOW

# ── Language codes (ISO 639-2) ────────────────────────────────────────────────
# Used in the metadata prompt. Add more if needed.
declare -A LANGUAGE_CODES=(
    [1]="eng"    [2]="spa"    [3]="fra"    [4]="deu"    [5]="ita"
    [6]="jpn"    [7]="por"    [8]="rus"    [9]="zho"    [10]="kor"
    [11]="ara"   [12]="swe"   [13]="nor"   [14]="dan"   [15]="fin"
    [16]="pol"   [17]="nld"   [18]="tur"   [19]="heb"   [20]="hin"
)

LANGUAGE_NAMES=(
    "1=English" "2=Spanish" "3=French" "4=German" "5=Italian"
    "6=Japanese" "7=Portuguese" "8=Russian" "9=Chinese" "10=Korean"
    "11=Arabic" "12=Swedish" "13=Norwegian" "14=Danish" "15=Finnish"
    "16=Polish" "17=Dutch" "18=Turkish" "19=Hebrew" "20=Hindi"
)

export LANGUAGE_CODES LANGUAGE_NAMES

# ── Common TV networks (for autocomplete prompt) ──────────────────────────────
COMMON_NETWORKS=(
    "ABC" "NBC" "CBS" "Fox" "HBO" "Showtime" "Starz" "Netflix" "Hulu"
    "Amazon Prime" "Disney+" "Apple TV+" "AMC" "FX" "BBC" "ITV" "Channel 4"
    "PBS" "Syfy" "Comedy Central" "MTV" "Cartoon Network" "Adult Swim"
    "Discovery" "History" "National Geographic" "TLC" "Bravo" "CNBC"
    "CNN" "Lifetime" "USA Network" "TNT" "TBS" "Peacock" "Paramount+"
    "WB" "The CW" "Nickelodeon" "Hallmark" "A&E" "truTV"
)

export COMMON_NETWORKS

# ── Movie ratings ─────────────────────────────────────────────────────────────
MOVIE_RATINGS=("G" "PG" "PG-13" "R" "NC-17" "NR" "Unrated")
TV_RATINGS=("TV-Y" "TV-Y7" "TV-G" "TV-PG" "TV-14" "TV-MA" "NR")

export MOVIE_RATINGS TV_RATINGS

# ── Common movie genres ───────────────────────────────────────────────────────
MOVIE_GENRES=(
    "Action" "Adventure" "Animation" "Biography" "Comedy" "Crime"
    "Documentary" "Drama" "Family" "Fantasy" "Film-Noir" "History"
    "Horror" "Music" "Musical" "Mystery" "Romance" "Sci-Fi"
    "Short" "Sport" "Thriller" "War" "Western"
)

TV_GENRES=(
    "Action" "Adventure" "Animation" "Comedy" "Crime" "Documentary"
    "Drama" "Family" "Fantasy" "Game Show" "History" "Horror"
    "Late Night" "Mini-Series" "Music" "Mystery" "News" "Reality"
    "Romance" "Sci-Fi" "Soap Opera" "Sports" "Talk Show" "Thriller"
    "Western"
)

export MOVIE_GENRES TV_GENRES

# ── Ensure queue and log dirs exist ──────────────────────────────────────────
mkdir -p "$QUEUE_DIR" "$LOG_DIR" "$TEMPLATE_DIR"
