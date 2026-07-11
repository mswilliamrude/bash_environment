#!/bin/bash

# --- Rick Roll Matrix ---
# Displays lyrics in a Matrix-style "digital rain" animation.

# Function to clean up terminal on exit
cleanup() {
    tput sgr0  # Reset all attributes
    tput cnorm # Make cursor visible again
    tput clear # Clear the screen
    stty echo  # Re-enable echoing of typed characters
    exit 0
}

# Trap Ctrl+C (INT signal) to run cleanup function
trap cleanup INT

# Terminal setup
stty -echo         # Disable echoing of typed characters
tput civis         # Make cursor invisible
tput clear         # Clear the screen
tput bold          # Set bold text
tput setaf 2       # Set foreground color to green

# Get terminal dimensions
width=$(tput cols)
height=$(tput lines)

# --- Complexity Calculation ---
# This section calculates the stream spawn probability based on the COMPLEXITY env var.
# The user-provided COMPLEXITY is treated as a percentage of a "maximum visual density",
# which we've calibrated to be what the script previously considered 1%.
# It defaults to 100 (the max) if the variable is not set.
COMPLEXITY=${COMPLEXITY:-100}

# Total cells on the screen
width=$(tput cols)
height=$(tput lines)
total_cells=$((width * height))

# Average visible length of a stream/tail. This is an approximation.
avg_stream_length=12 

# Calculate how many streams should be on screen to approximate the desired density.
# We scale the user's input (where 100 is the max) to our internal calculation (where 1% is the max).
if [ "$COMPLEXITY" -le 0 ]; then
    target_streams=0
else
    # The effective percentage is USER_COMPLEXITY / 100. So we divide the whole thing by 10000.
    target_filled_cells=$((total_cells * COMPLEXITY / 10000))
    target_streams=$((target_filled_cells / avg_stream_length))
    if [ "$target_streams" -eq 0 ] && [ "$COMPLEXITY" -gt 0 ]; then
        target_streams=1 # For any complexity > 0, we want at least one stream.
    fi
fi

# Convert the number of target streams into a spawn probability denominator.
# A lower number means a higher probability. This is a rough approximation.
if [ "$target_streams" -eq 0 ]; then
    # If complexity is 0, we set a denominator so large that spawning is practically impossible.
    spawn_chance_denominator=1000000
else
    spawn_chance_denominator=$((width * 2 / target_streams))
    if [ "$spawn_chance_denominator" -le 0 ]; then
        spawn_chance_denominator=1
    fi
fi



# Lyrics array
# Add Cyrillic, extended ASCII, and line drawing characters to the lyrics
lyrics=(
    "Never gonna give you up | Никогда не откажусь от тебя"
    "Never gonna let you down | Никогда тебя не подведу"
    "Never gonna run around and desert you | ║═╗ ╚╦╝"
    "Never gonna make you cry | Никогда не заставлю тебя плакать"
    "Never gonna say goodbye | Никогда не скажу прощай | ╔═╩═╗"
    "Never gonna tell a lie and hurt you | Никогда не солгу и не обижу тебя"
    "We've known each other for so long | Мы так давно знаем друг друга"
    "Your heart's been aching but you're too shy to say it | Твое сердце болит, но ты стесняешься сказать это"
    "Inside we both know what's been going on | Внутри мы оба знаем, что происходит | ╚═══╝"
    "We know the game and we're gonna play it | Мы знаем игру, и мы собираемся в нее играть | ╟───╢"
)

# Initialize columns array
# This array will hold the y-position of the "drip" for each column
declare -a cols
for ((i=0; i<width; i++)); do
    cols[i]=-1
done

# --- Animation Loop ---
# This is the main animation loop. It's an infinite loop that draws
# each frame of the animation.
while true; do
    # Iterate over each column of the terminal
    for ((i=0; i<width; i++)); do
        # Check if the current column has an active "drip"
        if [ ${cols[i]} -ge 0 ]; then
            # --- Draw the Drip ---
            
            # 1. Get the specific lyric line and character for this position
            lyric=${lyrics[${cols[i]} % ${#lyrics[@]}]}
            len=${#lyric}
            # Calculate the character index from the lyric string.
            # The character is based on the y and x position to create a varied, diagonal text effect.
            char_index=$(( (cols[i] - i) % len ))
            # Ensure the index is not negative
            if [ $char_index -lt 0 ]; then
                char_index=$((char_index + len))
            fi
            
            # 2. Draw the bright white "leader" character
            tput cup ${cols[i]} $i       # Move cursor to the current position
            tput setaf 15                # Set color to bright white
            echo -n "${lyric:$char_index:1}" # Print the character

            # 3. Draw the bright green "middle" character one position above the leader
            if [ ${cols[i]} -gt 0 ]; then
                tput cup $((${cols[i]} - 1)) $i
                tput setaf 10 # Set color to bright green
                # We need to recalculate the character for this position
                prev_char_index=$(( (cols[i] - 1 - i) % len ))
                if [ $prev_char_index -lt 0 ]; then
                    prev_char_index=$((prev_char_index + len))
                fi
                echo -n "${lyric:$prev_char_index:1}"
            fi

            # 4. Draw the dimmer green "tail" character two positions above
            if [ ${cols[i]} -gt 1 ]; then
                tput cup $((${cols[i]} - 2)) $i
                tput setaf 2 # Set color to normal green
                # We need to recalculate the character for this position
                prev_char_index=$(( (cols[i] - 2 - i) % len ))
                if [ $prev_char_index -lt 0 ]; then
                    prev_char_index=$((prev_char_index + len))
                fi
                echo -n "${lyric:$prev_char_index:1}"
            fi
            
            # 5. Erase the end of the tail to create the falling effect
            # The tail is set to a length of 12 characters.
            tail_end_pos=$((${cols[i]} - 12))
            if [ $tail_end_pos -ge 0 ]; then
                tput cup $tail_end_pos $i
                echo -n " "
            fi
            
            # --- Update Drip Position ---
            # Move the drip down for the next frame
            cols[i]=$((${cols[i]} + 1))
            
            # Reset the drip if it goes off the bottom of the screen
            # The drip is reset when its tail is fully off-screen.
            if [ $((${cols[i]} - 12)) -ge $height ]; then
                cols[i]=-1
            fi
        fi

        # --- Start New Drips ---
        # Randomly start a new drip in an inactive column based on the calculated probability.
        if [ ${cols[i]} -lt 0 ] && [ $((RANDOM % spawn_chance_denominator)) -eq 0 ]; then
            cols[i]=0
        fi
    done
    
    # Pause between frames to control animation speed
    sleep 0.05
done
