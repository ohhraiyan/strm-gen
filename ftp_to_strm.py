#!/usr/bin/env python3
"""
h5ai FTP Index -> Jellyfin .strm Generator
Scrapes h5ai fallback HTML, looks up clean title+year via TMDB API.
Naming follows Jellyfin standard: Movie Name (Year)/Movie Name (Year).strm
"""
import re
import time
import argparse
import urllib.parse
import requests
from bs4 import BeautifulSoup
from pathlib import Path

VIDEO_EXTS = {'mp4', '3gp', 'mkv', 'wmv', 'avi', 'flv', 'mov', 'ts', 'm4v'}

# ─── TMDB ─────────────────────────────────────────────────────────────────────

def extract_search_title(filename):
    """Pull a searchable title + year guess from a messy FTP filename."""
    stem = filename.rsplit(".", 1)[0]
    # Replace dots/underscores with spaces
    stem = re.sub(r"[._]", " ", stem)
    # Find year
    year_match = re.search(r"(19|20)\d{2}", stem)
    year = year_match.group() if year_match else None
    # Everything before the year (or before quality tags) is the title
    if year_match:
        title = stem[:year_match.start()].strip()
    else:
        # Cut off at common quality/release tags
        title = re.split(r"\b(1080p|720p|480p|2160p|4K|BluRay|WEB|HDTV|DVDRip|BRRip|x264|x265|HEVC|AAC|DDP|H264|H265)\b",
                         stem, flags=re.IGNORECASE)[0].strip()
    return title, year


def tmdb_lookup(title, year, api_key):
    """Search TMDB for the movie, return (clean_title, clean_year) or None."""
    if not api_key:
        return None

    params = {"api_key": api_key, "query": title, "language": "en-US"}
    if year:
        params["year"] = year

    try:
        r = requests.get("https://api.themoviedb.org/3/search/movie",
                         params=params, timeout=10)
        r.raise_for_status()
        results = r.json().get("results", [])
        if results:
            movie = results[0]
            clean_title = movie.get("title", title)
            release = movie.get("release_date", "")
            clean_year = release[:4] if release else year
            return clean_title, clean_year
    except Exception as e:
        print(f"    [TMDB WARN] {e}")
    return None


# ─── Helpers ──────────────────────────────────────────────────────────────────

def sanitize(name):
    return re.sub(r'[\\/*?:"<>|]', "", name).strip()


def make_folder_name(filename, api_key, tmdb_cache):
    """Return a clean 'Title (Year)' folder name."""
    search_title, year = extract_search_title(filename)

    cache_key = f"{search_title.lower()}_{year}"
    if cache_key in tmdb_cache:
        return tmdb_cache[cache_key]

    if api_key:
        result = tmdb_lookup(search_title, year, api_key)
        if result:
            clean_title, clean_year = result
            folder = sanitize(f"{clean_title} ({clean_year})")
            tmdb_cache[cache_key] = folder
            return folder

    # Fallback: use what we extracted locally
    if search_title and year:
        folder = sanitize(f"{search_title} ({year})")
    elif search_title:
        folder = sanitize(search_title)
    else:
        folder = sanitize(filename.rsplit(".", 1)[0])

    tmdb_cache[cache_key] = folder
    return folder


# ─── Crawler ──────────────────────────────────────────────────────────────────

def get_links(session, base_url, url):
    try:
        r = session.get(url, timeout=15)
        r.raise_for_status()
    except Exception as e:
        print(f"  [WARN] {url}: {e}")
        return []

    soup = BeautifulSoup(r.text, "html.parser")
    results = []
    for td in soup.select("td.fb-n"):
        a = td.find("a", href=True)
        if not a:
            continue
        href = a["href"]
        if not href.startswith("/") or href == "..":
            continue
        name = urllib.parse.unquote(href.rstrip("/").split("/")[-1])
        is_dir = href.endswith("/")
        full_url = urllib.parse.urljoin(base_url, href)
        results.append((name, full_url, is_dir))
    return results


def crawl(session, base_url, url, output_dir, depth, max_depth, api_key, tmdb_cache, stats):
    if depth > max_depth:
        return

    print(f"[DIR] {url}")
    entries = get_links(session, base_url, url)

    for name, full_url, is_dir in entries:
        ext = name.rsplit(".", 1)[-1].lower() if "." in name else ""

        if is_dir:
            time.sleep(0.15)
            crawl(session, base_url, full_url, output_dir,
                  depth + 1, max_depth, api_key, tmdb_cache, stats)

        elif ext in VIDEO_EXTS:
            folder_name = make_folder_name(name, api_key, tmdb_cache)
            movie_dir = output_dir / folder_name
            movie_dir.mkdir(parents=True, exist_ok=True)
            strm_path = movie_dir / f"{folder_name}.strm"
            strm_path.write_text(full_url, encoding="utf-8")
            source = "TMDB" if api_key else "local"
            print(f"  [OK:{source}] {folder_name}.strm")
            stats["count"] += 1


# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="h5ai FTP index to Jellyfin .strm")
    parser.add_argument("--url",      required=True,         help="Full URL to the FTP directory")
    parser.add_argument("--output",   default="./strm_output", help="Output folder")
    parser.add_argument("--depth",    type=int, default=4,   help="Max crawl depth (default 4)")
    parser.add_argument("--tmdb-key", default="",            help="TMDB API key for clean titles (optional)")
    args = parser.parse_args()

    parsed = urllib.parse.urlparse(args.url)
    base_url = f"{parsed.scheme}://{parsed.netloc}"

    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)

    session = requests.Session()
    session.headers["User-Agent"] = "Mozilla/5.0"

    tmdb_cache = {}
    stats = {"count": 0}

    if args.tmdb_key:
        print(f"TMDB   : enabled (clean titles from themoviedb.org)")
    else:
        print(f"TMDB   : disabled (using local title extraction)")
        print(f"         get a free key at https://www.themoviedb.org/settings/api")

    print(f"Base   : {base_url}")
    print(f"Output : {output_dir.resolve()}")
    print()

    crawl(session, base_url, args.url, output_dir,
          depth=0, max_depth=args.depth,
          api_key=args.tmdb_key,
          tmdb_cache=tmdb_cache,
          stats=stats)

    print(f"\nDone! {stats['count']} .strm file(s) created.")


if __name__ == "__main__":
    main()
