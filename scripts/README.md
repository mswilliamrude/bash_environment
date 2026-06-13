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
| `games/invaders.sh` | Pure bash ASCII Space Invaders (v3, 467 lines) |
