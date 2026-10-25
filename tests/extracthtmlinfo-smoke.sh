#!/usr/bin/env bash
# Static HTML CLI regression, no network or host modifications.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TOOL="$ROOT/bash/bin/recon/extracthtmlinfo.sh"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
cat >"$tmp/page.html" <<'HTML'
<!doctype html><html lang="es"><head><title>Vídeo de prueba</title>
<meta name="description" content="Página de prueba">
<meta property="og:video" content="/clip.mp4?token=private">
<script type="application/ld+json">{"@type":"VideoObject","contentUrl":"/stream.m3u8"}</script>
<script>const file="https://cdn.example.org/movie.mpd"; const api="/api/items"; debugger;</script>
<script src="/app.js"></script></head><body>
<h1>Hola <em>mundo</em></h1><p>Información útil</p>
<a href="/path?token=secret&x=2">Enlace</a><img src="/picture.png" alt="Foto">
<video poster="/poster.jpg" src="blob:https://example.org/uuid"><source src="/film.webm" type="video/webm"><track src="/subtitle.vtt" srclang="es"></video>
<iframe src="https://www.youtube.com/embed/123"></iframe>
<form method="post"><input type="hidden" name="password" value="must-not-appear"></form>
</body></html>
HTML
"$TOOL" >"$tmp/help.txt"
grep -q 'usage: extracthtmlinfo' "$tmp/help.txt"
"$TOOL" "$tmp/page.html" --base-url https://example.org/ --json >"$tmp/report.json"
python3 - "$tmp/report.json" <<'PY'
import json,sys
r=json.load(open(sys.argv[1],encoding='utf-8'))
assert r['summary']['title']=='Vídeo de prueba'
assert r['headings'][0]['text']=='Hola mundo'
assert r['links']['total']==1 and 'REDACTED' in r['links']['items'][0]['url']
assert r['media']['images'][0]['url']=='https://example.org/picture.png'
assert r['media']['videos'][0]['poster']=='https://example.org/poster.jpg'
assert r['media']['videos'][0]['sources'][0]['url']=='https://example.org/film.webm'
assert any('stream.m3u8' in x['url'] for x in r['media']['video_sources'])
assert any('movie.mpd' in x['url'] for x in r['media']['video_sources'])
assert any('clip.mp4' in x['url'] and 'REDACTED' in x['url'] for x in r['media']['video_sources'])
assert any('blob:' in x['url'] for x in r['media']['blob_urls'])
assert r['assets']['scripts'][0]['url']=='https://example.org/app.js'
assert 'must-not-appear' not in str(r)
assert 'https://example.org/api/items' in r['discovery']['possible_endpoints']
PY
cat "$tmp/page.html" | "$TOOL" - --sections summary,media | grep -q 'Vídeo de prueba'
! "$TOOL" "$tmp/page.html" --sections invalid >/dev/null 2>&1
! "$TOOL" "$tmp/page.html" --limit 0 >/dev/null 2>&1
printf 'PASS: extracthtmlinfo help, piping, media, JSON and redaction\n'
