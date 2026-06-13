#!/usr/bin/env python3
"""
dgdg.py - DuckDuckGo CLI Search (stdlib-only)

Zero-dependency web search using DuckDuckGo's HTML endpoint.
Originally created autonomously by an AI subagent during an HS/Link
protocol research session (May 31, 2026) when it needed to look
something up and simply... built its own search tool on the spot.

Usage:
    python3 dgdg.py "your search query here"
    python3 dgdg.py HS/Link file transfer protocol Samuel H. Smith
"""

import sys
import urllib.request
import urllib.parse
import re


def search(query):
    """Search DuckDuckGo HTML endpoint and print results."""
    url = f"https://html.duckduckgo.com/html/?q={urllib.parse.quote(query)}"
    req = urllib.request.Request(
        url, headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'}
    )
    try:
        html = urllib.request.urlopen(req).read().decode('utf-8')
        links = re.findall(
            r'<a class="result__snippet[^>]*href="([^"]+)"[^>]*>(.*?)</a>',
            html, re.IGNORECASE | re.DOTALL
        )
        for link, snippet in links:
            clean_snippet = re.sub(r'<[^>]+>', '', snippet).strip()
            print(f"{link}\n  {clean_snippet}\n")
        if not links:
            print("No results found.")
    except Exception as e:
        print(f"Error: {e}")


if __name__ == '__main__':
    if len(sys.argv) > 1:
        search(' '.join(sys.argv[1:]))
    else:
        print(__doc__.strip())
