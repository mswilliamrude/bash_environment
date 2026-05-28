#!/usr/bin/env bash
# ASCII Space Invaders in pure bash — v3.
# Adds: difficulty menu, level progression, enemy fire, lives,
# speed-up-as-they-die, hit flash, between-level splashes.
#
# Controls: ←/→ move, space fire, q quit.
# Run:  ./invaders.sh   (UTF-8 terminal; resize to at least 26x62)

set -u

# ===========================================================================
# Terminal setup / teardown
# ===========================================================================
cleanup() {
    stty sane 2>/dev/null
    printf '\e[?25h\e[0m\e[2J\e[H'
}
trap cleanup INT TERM EXIT

stty -echo -icanon time 0 min 0
printf '\e[?25l\e[2J'

# ===========================================================================
# Constants
# ===========================================================================
ROWS=24                                  # interior playfield height
COLS=60                                  # interior playfield width
TOTAL_ROWS=$((ROWS + 2))
TOTAL_COLS=$((COLS + 2))

# Colors
C_RESET=$'\e[0m'
C_BORDER=$'\e[1;34m'
C_HUD=$'\e[1;37m'
C_PLAYER=$'\e[1;32m'
C_PLAYER_HIT=$'\e[1;31m'                 # red flash on hit
C_BULLET=$'\e[1;33m'                     # player bullets — yellow
C_EBULLET=$'\e[1;31m'                    # enemy bullets — red
C_A1=$'\e[1;31m'
C_A2=$'\e[1;35m'
C_A3=$'\e[1;36m'
C_TITLE=$'\e[1;33m'
C_DIM=$'\e[2;37m'

# Glyphs
G_PLAYER='▲'
G_BULLET='╿'                             # player shot, going up
G_EBULLET='╽'                            # enemy shot, going down
G_A1='Ψ'
G_A2='Ж'
G_A3='Ѫ'
G_H='═'; G_V='║'
G_TL='╔'; G_TR='╗'; G_BL='╚'; G_BR='╝'

# ===========================================================================
# Difficulty presets
#   $1 = difficulty name → sets globals:
#     diff_name, lives, base_move_period, base_fire_chance, score_mult
#   base_move_period: aliens move every N frames (lower = faster)
#   base_fire_chance: out of 1000, probability per frame any one alien fires
# ===========================================================================
apply_difficulty() {
    case $1 in
        easy)
            diff_name="Easy"
            lives=5
            base_move_period=12
            base_fire_chance=5      # 0.5% per frame
            score_mult=1
            ;;
        normal)
            diff_name="Normal"
            lives=3
            base_move_period=8
            base_fire_chance=15     # 1.5%
            score_mult=2
            ;;
        hard)
            diff_name="Hard"
            lives=2
            base_move_period=5
            base_fire_chance=30     # 3%
            score_mult=3
            ;;
    esac
}

# ===========================================================================
# Drawing helpers
# ===========================================================================
draw_border() {
    local r c buf="\e[H${C_BORDER}"
    buf+="\e[1;1H${G_TL}"
    for ((c = 0; c < COLS; c++)); do buf+="${G_H}"; done
    buf+="${G_TR}"
    buf+="\e[${TOTAL_ROWS};1H${G_BL}"
    for ((c = 0; c < COLS; c++)); do buf+="${G_H}"; done
    buf+="${G_BR}"
    for ((r = 2; r < TOTAL_ROWS; r++)); do
        buf+="\e[${r};1H${G_V}\e[${r};${TOTAL_COLS}H${G_V}"
    done
    buf+="${C_RESET}"
    printf '%b' "$buf"
}

# Centered text on a given row (1-indexed, within the bordered frame).
center_text() {
    local row=$1 text=$2 color=${3:-$C_HUD}
    # Strip ANSI escapes for length calc — assume plain text passed in
    local len=${#text}
    local col=$(( (TOTAL_COLS - len) / 2 + 1 ))
    printf '\e[%d;%dH%s%s%s' "$row" "$col" "$color" "$text" "$C_RESET"
}

# Pause for keyboard flush + N seconds
splash_pause() {
    local secs=$1
    # Drain any pending input so a held key doesn't skip
    while IFS= read -rsn1 -t 0.001 _; do :; done
    sleep "$secs"
}

# ===========================================================================
# Splash screens
# ===========================================================================
splash_title() {
    printf '\e[2J'
    draw_border
    center_text 4 "A S C I I   I N V A D E R S" "$C_TITLE"
    center_text 6 "pure bash · v3" "$C_DIM"

    center_text 10 "Select difficulty:" "$C_HUD"
    center_text 12 "[1]  Easy    — 5 lives, slow aliens, 1× score" "$C_A3"
    center_text 13 "[2]  Normal  — 3 lives, medium speed,  2× score" "$C_A2"
    center_text 14 "[3]  Hard    — 2 lives, fast aliens,   3× score" "$C_A1"

    center_text 18 "←/→ move    space fire    q quit" "$C_DIM"
    center_text 20 "press 1, 2 or 3 to begin" "$C_HUD"

    # Block until a valid choice
    local k
    while true; do
        IFS= read -rsn1 k
        case $k in
            1) apply_difficulty easy;   return ;;
            2) apply_difficulty normal; return ;;
            3) apply_difficulty hard;   return ;;
            q|Q) exit 0 ;;
        esac
    done
}

splash_level() {
    local level=$1
    printf '\e[2J'
    draw_border
    center_text 11 "L E V E L   ${level}" "$C_TITLE"
    center_text 13 "get ready..." "$C_DIM"
    splash_pause 1.2
}

splash_gameover() {
    local won=$1 final=$2 level=$3
    printf '\e[2J'
    draw_border
    if ((won)); then
        center_text 10 "★  V I C T O R Y  ★" "$C_A3"
    else
        center_text 10 "G A M E   O V E R" "$C_A1"
    fi
    center_text 13 "Final score: ${final}" "$C_HUD"
    center_text 14 "Reached level: ${level}" "$C_HUD"
    center_text 16 "Difficulty: ${diff_name}" "$C_DIM"
    splash_pause 0.3
    # Park cursor below the frame so the prompt looks clean
    printf '\e[%d;1H\e[0m\n' "$((TOTAL_ROWS + 1))"
}

# ===========================================================================
# Level setup — populate aliens, reset bullets, set per-level params
# ===========================================================================
init_level() {
    local level=$1

    # Start row drops one each level, up to a floor
    local start_row=2
    ((start_row += level - 1))
    ((start_row > 6)) && start_row=6

    aliens=()
    local r1=$((start_row))
    local r2=$((start_row + 2))
    local r3=$((start_row + 4))
    local c
    for c in $(seq 6 4 54); do aliens+=("${r1},${c},1"); done
    for c in $(seq 6 4 54); do aliens+=("${r2},${c},2"); done
    for c in $(seq 6 4 54); do aliens+=("${r3},${c},3"); done

    initial_alien_count=${#aliens[@]}

    bullets=()
    ebullets=()
    adir=1
    atick=0
    px=$((COLS / 2))

    # Per-level scaling — aliens move 1 frame faster per level (floor 2),
    # enemy fire chance grows ~30% per level.
    level_move_period=$(( base_move_period - (level - 1) ))
    ((level_move_period < 2)) && level_move_period=2
    # bash has no float math — approximate ×1.3^(level-1) with integer growth
    level_fire_chance=$base_fire_chance
    local i
    for ((i = 1; i < level; i++)); do
        level_fire_chance=$(( level_fire_chance * 13 / 10 ))
    done
    ((level_fire_chance > 200)) && level_fire_chance=200   # cap at 20%
}

# ===========================================================================
# Per-frame renderer
# ===========================================================================
draw() {
    local buf="\e[H" r blank
    printf -v blank '%*s' "$COLS" ''
    for ((r = 2; r < TOTAL_ROWS; r++)); do
        buf+="\e[${r};2H${blank}"
    done

    # HUD on top border
    local hud
    hud=$(printf ' Score: %05d  Lives: %d  Level: %d  Diff: %s  [q quit] ' \
        "$score" "$lives" "$level" "$diff_name")
    buf+="\e[1;3H${C_HUD}${hud}${C_RESET}"

    # Aliens
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

    # Player bullets
    local b br bc
    for b in "${bullets[@]}"; do
        IFS=, read -r br bc <<<"$b"
        buf+="\e[$((br + 1));$((bc + 1))H${C_BULLET}${G_BULLET}${C_RESET}"
    done

    # Enemy bullets
    for b in "${ebullets[@]}"; do
        IFS=, read -r br bc <<<"$b"
        buf+="\e[$((br + 1));$((bc + 1))H${C_EBULLET}${G_EBULLET}${C_RESET}"
    done

    # Player — flash red on hit_flash > 0
    local pcolor=$C_PLAYER
    ((hit_flash > 0)) && pcolor=$C_PLAYER_HIT
    buf+="\e[$((ROWS + 1));$((px + 1))H${pcolor}${G_PLAYER}${C_RESET}"

    printf '%b' "$buf"
}

score_for_kind() {
    case $1 in 1) echo 30 ;; 2) echo 20 ;; 3) echo 10 ;; esac
}

# ===========================================================================
# Main game loop for one level. Returns 0 if cleared, 1 if player died out.
# ===========================================================================
play_level() {
    init_level "$level"
    hit_flash=0
    local invuln=0       # frames of invulnerability after a hit
    local k k2 i

    while true; do
        # ---- Input ----
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
                    q|Q) lives=0; return 1 ;;
                esac
            fi
        fi

        # ---- Move player bullets up ----
        local new=()
        for b in "${bullets[@]}"; do
            IFS=, read -r br bc <<<"$b"
            ((br--))
            ((br >= 1)) && new+=("${br},${bc}")
        done
        bullets=("${new[@]}")

        # ---- Move enemy bullets down ----
        new=()
        for b in "${ebullets[@]}"; do
            IFS=, read -r br bc <<<"$b"
            ((br++))
            ((br <= ROWS)) && new+=("${br},${bc}")
        done
        ebullets=("${new[@]}")

        # ---- Speed-up-as-they-die: shorten period as aliens are killed ----
        # remaining/initial ratio drives an effective period between
        # level_move_period and max(2, level_move_period/3).
        local remaining=${#aliens[@]}
        local effective_period=$level_move_period
        if ((remaining > 0 && initial_alien_count > 0)); then
            # Map remaining ∈ [1..initial] to period ∈ [floor..level_move_period]
            local floor=$(( level_move_period / 3 ))
            ((floor < 2)) && floor=2
            local span=$(( level_move_period - floor ))
            effective_period=$(( floor + span * remaining / initial_alien_count ))
            ((effective_period < 2)) && effective_period=2
        fi

        # ---- Move aliens ----
        if (( ++atick % effective_period == 0 )); then
            new=()
            for a in "${aliens[@]}"; do
                IFS=, read -r ar ac ak <<<"$a"
                ((ac += adir))
                new+=("${ar},${ac},${ak}")
            done
            aliens=("${new[@]}")

            local bounced=0
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

        # ---- Enemy fire ----
        # Iterate aliens; each rolls level_fire_chance/1000 to fire.
        # Cap simultaneous enemy bullets to keep things sane.
        local max_ebullets=$(( 4 + level ))
        if ((${#ebullets[@]} < max_ebullets)); then
            for a in "${aliens[@]}"; do
                if (( RANDOM % 1000 < level_fire_chance )); then
                    IFS=, read -r ar ac ak <<<"$a"
                    ebullets+=("$((ar + 1)),${ac}")
                    ((${#ebullets[@]} >= max_ebullets)) && break
                fi
            done
        fi

        # ---- Player bullets vs aliens ----
        local survivors=() hit_b=()
        for a in "${aliens[@]}"; do
            IFS=, read -r ar ac ak <<<"$a"
            local killed=0
            for i in "${!bullets[@]}"; do
                IFS=, read -r br bc <<<"${bullets[$i]}"
                if ((br == ar && bc == ac)); then
                    killed=1; hit_b+=("$i"); break
                fi
            done
            if ((killed)); then
                local pts
                pts=$(score_for_kind "$ak")
                (( score += pts * score_mult ))
            else
                survivors+=("$a")
            fi
        done
        aliens=("${survivors[@]}")
        for i in "${hit_b[@]}"; do unset 'bullets[i]'; done
        bullets=("${bullets[@]}")

        # ---- Enemy bullets vs player ----
        if ((invuln == 0)); then
            local hit_eb=() new_eb=()
            for i in "${!ebullets[@]}"; do
                IFS=, read -r br bc <<<"${ebullets[$i]}"
                if (( br == ROWS && bc == px )); then
                    hit_eb+=("$i")
                fi
            done
            if ((${#hit_eb[@]} > 0)); then
                ((lives--))
                hit_flash=8
                invuln=20
                for i in "${hit_eb[@]}"; do unset 'ebullets[i]'; done
                ebullets=("${ebullets[@]}")
                if ((lives <= 0)); then
                    draw                   # show final frame
                    return 1
                fi
            fi
        else
            ((invuln--))
        fi
        ((hit_flash > 0)) && ((hit_flash--))

        # ---- Aliens reaching the floor = instant game over ----
        for a in "${aliens[@]}"; do
            IFS=, read -r ar ac ak <<<"$a"
            if ((ar >= ROWS)); then
                lives=0
                return 1
            fi
        done

        # ---- Level cleared ----
        if ((${#aliens[@]} == 0)); then
            draw
            return 0
        fi

        draw
        sleep 0.05
    done
}

# ===========================================================================
# Top-level driver
# ===========================================================================
splash_title                              # sets diff_name, lives, base_*

score=0
level=1
won=0

while true; do
    splash_level "$level"
    if play_level; then
        ((level++))
        # No hard cap on levels — keeps speeding up to the floor.
        # Optional: stop at level 10 and declare victory.
        if ((level > 10)); then
            won=1
            break
        fi
    else
        break
    fi
done

splash_gameover "$won" "$score" "$level"
