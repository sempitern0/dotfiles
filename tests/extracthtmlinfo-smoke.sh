#!/usr/bin/env bash
# Static HTML CLI smoke tests; no network access or host modifications.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TOOL="$ROOT/bash/bin/recon/extracthtmlinfo.sh"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
cat >"$tmp/page.html" <<'HTML'
<!doctype html><html lang="es"><head><title>Demo HTML</title>
<meta name="description" content="Página de prueba">
<link rel="canonical" href="/home"><script src="/app.js"></script>
<script type="application/ld+json">{"@type":"Organization","name":"Demo"}</script>
<script>const path="/api/items"; debugger;</script>
</head><body><h1>Hola <em>mundo</em></h1>
<p>Información útil.</p><a href="/path?token=secret&x=2">Link</a>
<img src="/picture.png" alt="Demo image">
<form method="post"><input type="hidden" name="password" value="must-not-appear"></form>
</body></html>
HTML
"$TOOL" "$tmp/page.html" --base-url https://example.org/ --json >"$tmp/report.json"
python3 - "$tmp/report.json" <<'PY'
import json,sys
r=json.load(open(sys.argv[1],encoding='utf8'))
assert r['summary']['title']=='Demo HTML'
assert r['summary']['language']=='es'
assert r['headings'][0]['text']=='Hola mundo'
assert r['links']['total']==1
assert 'REDACTED' in r['links']['items'][0]['url']
assert 'must-not-appear' not in str(r)
assert r['media']['images'][0]['url']=='https://example.org/picture.png'
assert r['assets']['scripts'][0]['url']=='https://example.org/app.js'
assert r['metadata']['json_ld'][0]['type']=='Organization'
assert 'https://example.org/api/items' in r['discovery']['possible_endpoints']
PY
cat "$tmp/page.html" | "$TOOL" - --sections summary,headings | grep -q 'Demo HTML'
! "$TOOL" "$tmp/page.html" --sections does-not-exist >/dev/null 2>&1
! "$TOOL" "$tmp/page.html" --limit 0 >/dev/null 2>&1
echo 'PASS: extracthtmlinfo local/pipe/JSON/redaction/options'
