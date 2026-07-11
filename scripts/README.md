# scripts/

Standalone utility scripts. These live outside `.bashrc.d/` because they're
invoked directly rather than sourced at shell startup.

## Scripts

### `dgdg.py` - DuckDuckGo CLI Search

Zero-dependency Python web search using DuckDuckGo's HTML endpoint.  
No API keys, no pip installs - just stdlib `urllib` and `re`.

```bash
python3 scripts/dgdg.py "HS/Link file transfer protocol"
```

**Origin story:** This script was created autonomously by an AI subagent
during an HS/Link protocol research session (May 2026). The agent needed
to search the web for documentation on a 1994 BBS file transfer protocol
and - having no search tool available - simply built one on the spot in
16 lines of Python. It was too useful (and too cheeky) to throw away.

---

### `rr_matrix.sh` - Matrix Digital Rain (Rickroll Edition)

Matrix-style "digital rain" animation with rickroll lyrics scrolling down
in green text. Features Cyrillic characters and box-drawing symbols mixed
with the English lyrics for that authentic Matrix aesthetic.

```bash
# Default density (100% = maximum visual chaos)
./scripts/rr_matrix.sh

# Adjust rain density via COMPLEXITY (0-100)
COMPLEXITY=50 ./scripts/rr_matrix.sh   # medium density
COMPLEXITY=10 ./scripts/rr_matrix.sh   # sparse rain
COMPLEXITY=1  ./scripts/rr_matrix.sh   # minimal (zen mode)
```

**Controls:** `Ctrl+C` to exit (restores terminal state cleanly).

**How it works:** Each column has an independent "drip" that scrolls down,
leaving a fading trail. The spawn probability is calculated from terminal
dimensions and the COMPLEXITY percentage. At COMPLEXITY=100, approximately
1% of screen cells are filled with active streams at any moment.

**Lines:** 171

---

### `animated_rick.sh` - Animated Rick Astley ASCII Art

Frame-by-frame ASCII animation of Rick Astley rendered in 24-bit ANSI
color escape sequences. This is the full rickroll experience - a complete
animated portrait that plays in your terminal.

```bash
./scripts/animated_rick.sh
```

**Requirements:** Terminal with 24-bit (truecolor) support.  
**Controls:** `Ctrl+C` to exit.

**Technical notes:** The script contains embedded ANSI escape sequences
that encode the RGB color values for each character cell. Each "frame"
is a 200-column wide image. The file is 258KB because it literally
contains the pixel data as escape codes.

**Lines:** 353

---

### `crawl_rick.sh` - Star Wars Crawl (Rickroll Edition)

Star Wars opening crawl effect with rickroll lyrics scrolling upward
over a static Rick Astley ASCII art background. Text transitions through
5 font sizes (large at bottom → tiny at top) and fades from bright
Star Wars yellow through amber to dark as it recedes.

```bash
./scripts/crawl_rick.sh
```

**Requirements:**
- `toilet` with figlet fonts (for the multi-size text rendering)
- Terminal with 24-bit color support
- Minimum ~80 columns recommended

**How it works:** The script draws the ANSI art background once, then
renders each chorus line through progressively smaller toilet fonts as
it scrolls upward. Only the character cells occupied by text are
overwritten; the rest of the image shows through.

**Fonts used (bottom to top):**
- `mono9` - largest, brightest (entry point)
- `letter` - large ASCII
- `smblock` - medium
- `pagga` - small
- `smbraille` - tiny, dim (exit point)

**Lines:** 547

---

## See Also

Other scriptable components in this repo:

| Path | Description |
|------|-------------|
| `.bashrc.d/01-windows_path.sh` | Windows/WSL PATH integration |
| `.bashrc.d/10-windows_env.sh` | Windows environment variable bridging |
| `.bashrc.d/15-ssh_agent.sh` | Cross-platform SSH agent reuse (Linux/macOS/MSYS2) |
| `.bashrc.d/20-vim.sh` | Vim configuration and aliases |
| `.bashrc.d/30-azure_routing.sh` | Azure bastion topology routing (600-line beast) |
| `.bashrc.d/30-history.sh` | Shell history management |
| `games/invaders.sh` | Pure bash ASCII Space Invaders (v3, 227 lines) |
