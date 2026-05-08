# 📡 FTP → Jellyfin STRM Generator

Convert any **h5ai FTP HTTP index** into a clean Jellyfin-ready `.strm` library — instantly.

```
FTP Index                         Jellyfin Library
─────────────────────────         ──────────────────────────
/English Movies (1080p)/          strm_output/
  (2024) 1080p/          →          Dune Part Two (2024)/
    Dune.Part.Two.2024.mkv              Dune Part Two (2024).strm
    Deadpool.3.2024.mkv           Deadpool & Wolverine (2024)/
                                      Deadpool & Wolverine (2024).strm
```

Each `.strm` file contains the direct HTTP stream URL — Jellyfin plays it straight from the FTP server, no downloading needed.

---

## ✨ Features

- 🖥️ **Interactive TUI** — step-by-step terminal UI, no flags to memorize
- 🎬 **TMDB integration** — clean movie titles matched from [themoviedb.org](https://www.themoviedb.org)
- 🔁 **Auto venv** — creates and installs Python dependencies automatically
- 🗂️ **Jellyfin naming** — outputs `Movie Name (Year)/Movie Name (Year).strm`
- 🌐 **h5ai aware** — scrapes the h5ai fallback table, ignores UI junk links
- 🔑 **Saved API key** — TMDB key saved to `~/.strm_tmdb_key`, enter once

---

## 🚀 Quick Start

```bash
git clone https://github.com/yourusername/strm-gen
cd strm-gen
chmod +x strm_tui.sh
./strm_tui.sh
```

That's it. The script handles everything else.

---

## 📋 Requirements

- Python 3.8+
- bash
- Internet access (for TMDB lookups — optional)

> `requests` and `beautifulsoup4` are installed automatically into a venv on first run.

---

## 🎛️ Manual Usage (no TUI)

```bash
# Activate venv first
source ~/strm-env/bin/activate

# Basic
python ftp_to_strm.py --url "http://172.16.50.14/DHAKA-FLIX-14/English%20Movies%20%281080p%29/" --output ~/strm_output

# With TMDB for clean titles
python ftp_to_strm.py \
  --url "http://172.16.50.14/DHAKA-FLIX-14/English%20Movies%20%281080p%29/" \
  --output ~/strm_output \
  --tmdb-key YOUR_API_KEY \
  --depth 4
```

| Flag | Default | Description |
|------|---------|-------------|
| `--url` | required | FTP HTTP index URL |
| `--output` | `./strm_output` | Output folder |
| `--depth` | `4` | Max subfolder crawl depth |
| `--tmdb-key` | _(none)_ | TMDB API key for clean titles |

---

## 🔑 TMDB API Key (Optional but Recommended)

1. Create a free account at [themoviedb.org](https://www.themoviedb.org)
2. Go to **Settings → API → Request an API key**
3. Copy your key and paste it when the TUI asks

Without a key, titles are extracted locally from the filename (still works, less accurate for messy names).

---

## 📁 Repo Structure

```
strm-gen/
├── ftp_to_strm.py   # Crawler + STRM generator
├── strm_tui.sh      # Interactive TUI launcher
└── README.md
```

---

## 🗒️ Notes

- Works with **h5ai** directory listings (common on Bangladeshi FTP servers like DHAKA-FLIX, CircleFTP, etc.)
- Jellyfin naming follows the [official docs](https://jellyfin.org/docs/general/server/media/movies/) — `Movie Name (Year)/Movie Name (Year).strm`
- STRM files stream directly — no storage used on your machine

---

## 📜 License

MIT
