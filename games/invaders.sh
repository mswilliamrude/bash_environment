#!/usr/bin/env bash
# ASCII Space Invaders in pure bash — v2 (Unicode + ANSI color).
# Controls: Left/Right arrows to move, Space to shoot, q to quit.
# Run:  ./invaders.sh   (terminal must be UTF-8; resize to at least 26x62)

set -u

# ---- Terminal setup / teardown ----
cleanup() {
    stty sane 2>/dev/null
    printf '\e[?25h\e[0m\e[2J\e[H'   # show cursor, reset color, clear, home
}
trap cleanup INT TERM EXIT

stty -echo -icanon time 0 min 0
printf '\e[?25l\e[2J'                # hide cursor, clear screen

# ---- Game constants ----
ROWS=24                              # interior height (playfield)
COLS=60                              # interior width
# Border lives at row 0 / row ROWS+1 / col 0 / col COLS+1.
# Playfield coords run row=1..ROWS, col=1..COLS, offset by +1 when drawn.
TOTAL_ROWS=$((ROWS + 2))
TOTAL_COLS=$((COLS + 2))

# ---- Colors (ANSI SGR) ----
C_RESET=$'\e[0m'
C_BORDER=$'\e[1;34m'                 # bright blue
C_HUD=$'\e[1;37m'                    # bright white
C_PLAYER=$'\e[1;32m'                 # bright green
C_BULLET=$'\e[1;33m'                 # bright yellow
C_A1=$'\e[1;31m'                     # row 1: red (top, hardest to hit)
C_A2=$'\e[1;35m'                     # row 2: magenta
C_A3=$'\e[1;36m'                     # row 3: cyan

# ---- Glyphs ----
G_PLAYER='▲'
G_BULLET='╿'
G_A1='Ψ'                             # top row
G_A2='Ж'                             # middle row
G_A3='Ѫ'                             # bottom row
G_H='═'; G_V='║'                     # border horiz/vert
G_TL='╔'; G_TR='╗'; G_BL='╚'; G_BR='╝'

# ---- Game state ----
px=$((COLS / 2))                     # player column (1..COLS)
bullets=()                           # "row,col"
aliens=()                            # "row,col,kind"   kind ∈ {1,2,3}
for c in $(seq 6 4 54); do aliens+=("2,${c},1"); done
for c in $(seq 6 4 54); do aliens+=("4,${c},2"); done
for c in $(seq 6 4 54); do aliens+=("6,${c},3"); done
adir=1
atick=0
score=0
running=1

# ---- Static border (drawn once, on top of clear) ----
draw_border() {
    local r c buf="\e[H${C_BORDER}"
    # Top
    buf+="\e[1;1H${G_TL}"
    for ((c = 0; c < COLS; c++)); do buf+="${G_H}"; done
    buf+="${G_TR}"
    # Bottom
    buf+="\e[${TOTAL_ROWS};1H${G_BL}"
    for ((c = 0; c < COLS; c++)); do buf+="${G_H}"; done
    buf+="${G_BR}"
    # Sides
    for ((r = 2; r < TOTAL_ROWS; r++)); do
        buf+="\e[${r};1H${G_V}\e[${r};${TOTAL_COLS}H${G_V}"
    done
    buf+="${C_RESET}"
    printf '%b' "$buf"
}

# ---- Renderer (called per frame) ----
draw() {
    local buf="\e[H"
    local r blank

    # Clear interior rows only — leave border intact
    printf -v blank '%*s' "$COLS" ''
    for ((r = 2; r < TOTAL_ROWS; r++)); do
        buf+="\e[${r};2H${blank}"
    done

    # HUD on top border (overwrites a section of it — intentional)
    buf+="\e[1;3H${C_HUD} Score: $(printf '%04d' "$score")  Aliens: $(printf '%3d' "${#aliens[@]}")  [←→ move · space fire · q quit] ${C_RESET}${C_BORDER}═${C_RESET}"

    # Aliens (offset +1 for border)
    local a ar ac ak color glyph
    for a in "${aliens[@]}"; do
        IFS=, read -r ar ac ak <<<"$a"
        case $ak in
            1) color=$C_A1; glyph=$G_A1 ;;
            2) color=$C_A2; glyph=$G_A2 ;;
            3) color=$C_A3; glyph=$G_A3 ;;
        esac
        buf+="\e[$((ar + 1));$((ac + 1))H${color}${glyph}${C_RESET}"
    done

    # Bullets
    local b br bc
    for b in "${bullets[@]}"; do
        IFS=, read -r br bc <<<"$b"
        buf+="\e[$((br + 1));$((bc + 1))H${C_BULLET}${G_BULLET}${C_RESET}"
    done

    # Player (bottom playfield row)
    buf+="\e[$((ROWS + 1));$((px + 1))H${C_PLAYER}${G_PLAYER}${C_RESET}"

    printf '%b' "$buf"
}

# Per-kind score values — top row worth more, like the original
score_for_kind() {
    case $1 in
        1) echo 30 ;;
        2) echo 20 ;;
        3) echo 10 ;;
    esac
}

# ---- Initial border paint ----
draw_border

# ---- Main loop ----
while ((running)); do

    # ---- Input (non-blocking) ----
    if IFS= read -rsn1 -t 0.001 k; then
        if [[ $k == $'\e' ]]; then
            read -rsn2 -t 0.001 k2 || k2=""
            case $k2 in
                "[D") ((px > 1))    && ((px--)) ;;
                "[C") ((px < COLS)) && ((px++)) ;;
            esac
        else
            case $k in
                ' ') bullets+=("$((ROWS - 1)),${px}") ;;
                q|Q) running=0 ;;
            esac
        fi
    fi

    # ---- Move bullets up ----
    new=()
    for b in "${bullets[@]}"; do
        IFS=, read -r br bc <<<"$b"
        ((br--))
        ((br >= 1)) && new+=("${br},${bc}")
    done
    bullets=("${new[@]}")

    # ---- Move aliens every 8 frames ----
    if (( ++atick % 8 == 0 )); then
        new=()
        for a in "${aliens[@]}"; do
            IFS=, read -r ar ac ak <<<"$a"
            ((ac += adir))
            new+=("${ar},${ac},${ak}")
        done
        aliens=("${new[@]}")

        # Bounce + drop a row if any alien hit an edge
        bounced=0
        for a in "${aliens[@]}"; do
            IFS=, read -r ar ac ak <<<"$a"
            if ((ac <= 1 || ac >= COLS)); then
                bounced=1
                break
            fi
        done
        if ((bounced)); then
            adir=$(( -adir ))
            new=()
            for a in "${aliens[@]}"; do
                IFS=, read -r ar ac ak <<<"$a"
                ((ar++))
                new+=("${ar},${ac},${ak}")
            done
            aliens=("${new[@]}")
        fi
    fi

    # ---- Collisions ----
    survivors=()
    hit_b=()
    for a in "${aliens[@]}"; do
        IFS=, read -r ar ac ak <<<"$a"
        killed=0
        for i in "${!bullets[@]}"; do
            IFS=, read -r br bc <<<"${bullets[$i]}"
            if ((br == ar && bc == ac)); then
                killed=1
                hit_b+=("$i")
                break
            fi
        done
        if ((killed)); then
            ((score += $(score_for_kind "$ak")))
        else
            survivors+=("$a")
        fi
    done
    aliens=("${survivors[@]}")
    for i in "${hit_b[@]}"; do unset 'bullets[i]'; done
    bullets=("${bullets[@]}")

    # ---- Win / lose ----
    if ((${#aliens[@]} == 0)); then
        printf '\e[H\e[2J\e[0m\n  *** YOU WIN! Score: %d ***\n\n' "$score"
        running=0
        continue
    fi
    for a in "${aliens[@]}"; do
        IFS=, read -r ar ac ak <<<"$a"
        if ((ar >= ROWS)); then
            printf '\e[H\e[2J\e[0m\n  *** GAME OVER. Score: %d ***\n\n' "$score"
            running=0
            break
        fi
    done

    draw
    sleep 0.05
done
