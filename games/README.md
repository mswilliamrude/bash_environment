# games/

Terminal games written in pure bash. No dependencies beyond a UTF-8 terminal.

## Games

### `invaders.sh` - ASCII Space Invaders

A complete Space Invaders clone in 227 lines of bash. Features difficulty
selection, level progression, enemy fire, lives, speed-up-as-they-die
mechanic, hit flash effects, and between-level splash screens.

```bash
./games/invaders.sh
```

**Requirements:** UTF-8 terminal, minimum 26 rows x 62 columns.  
**Controls:** Arrow keys to move, space to fire, `q` to quit.

---

*Why is this in a shell environment repo?* Because sometimes you're waiting
for a 45-minute Azure deployment and `invaders.sh` is right there in your PATH.
