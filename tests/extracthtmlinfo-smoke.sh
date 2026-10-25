#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TOOL="$ROOT/bash/bin/recon/extracthtmlinfo.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
cat >"$TMP/page.html" <<'HTML'
<!doctype html><html lang="es"><head><title>Vídeo</title>
<meta property="og:video" content="/watch.mp4?token=secret">
<script>const endpoint="/api/items"; debugger; const source="/stream.m3u8";</script>
</head><body><h1>Hola <em>mundo</em></h1>
<a href="/article?token=private">Artículo</a><img src="/image.png" alt="Portada">
<video src="blob:https://example.org/id"><source src="/clip.webm"><track src="/sub.vtt"></video>
<form><input name="inside" value="private-input"></form><input name="outside">
</body></html>
HTML
"$TOOL" >"$TMP/help"
grep -q 'QUICK EXAMPLES' "$TMP/help"
grep -q -- '--video-sources' "$TMP/help"
"$TOOL" --help >"$TMP/extended"
grep -q 'Images, video and audio filters' "$TMP/extended"
grep -q 'Form actions, methods and field names' "$TMP/extended"
if "$TOOL" --videos >"$TMP/stdout" 2>"$TMP/stderr"; then exit 1; fi
grep -q 'missing FILE or URL' "$TMP/stderr"
"$TOOL" "$TMP/page.html" --base-url https://example.org/ --json --quiet >"$TMP/result.json"
python3 - "$TMP/result.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
assert d['summary']['title']=='Vídeo'
assert d['headings'][0]['text']=='Hola mundo'
assert 'REDACTED' in d['links']['items'][0]['url']
assert d['forms'][0]['fields']==[{'name':'inside','type':'input'}]
assert 'private-input' not in str(d)
assert any('stream.m3u8' in x['url'] for x in d['media']['video_sources'])
assert d['media']['videos'][0]['sources'][0]['url']=='https://example.org/clip.webm'
assert any(x['url'].startswith('blob:') for x in d['media']['blob_urls'])
assert 'https://example.org/api/items' in d['discovery']['possible_endpoints']
PY
"$TOOL" "$TMP/page.html" --images --videos --json --quiet >"$TMP/filtered.json"
python3 - "$TMP/filtered.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
assert list(d)==['media'] and set(d['media'])=={'images','videos','video_sources'}
PY
cat "$TMP/page.html" | "$TOOL" - --sections summary --quiet | grep -q 'Vídeo'
for opt in '--limit 0' '--sections invalid' '--timeout 0'; do
    read -r -a params <<< "$opt"
    if "$TOOL" "$TMP/page.html" "${params[@]}" >/dev/null 2>"$TMP/error"; then exit 1; fi
    grep -Eq 'error:|ERROR' "$TMP/error"
done
python3 - "$TOOL" <<'PY'
import json, subprocess, sys, threading
from http.server import HTTPServer, BaseHTTPRequestHandler
class Handler(BaseHTTPRequestHandler):
    def log_message(self,*a): pass
    def do_GET(self):
        if self.path=='/move':
            self.send_response(302);self.send_header('Location','/page');self.end_headers();return
        if self.path=='/missing':self.send_error(404);return
        if self.path=='/binary':
            self.send_response(200);self.send_header('Content-Type','image/png');self.end_headers();self.wfile.write(b'PNG');return
        body=b'<!doctype html><html><body><video src="/film.mp4"></video></body></html>'
        self.send_response(200);self.send_header('Content-Type','text/html');self.end_headers();self.wfile.write(body)
server=HTTPServer(('127.0.0.1',0),Handler)
threading.Thread(target=server.serve_forever,daemon=True).start()
base=f'http://127.0.0.1:{server.server_port}'
def run(path):
    return subprocess.run(['bash',sys.argv[1],base+path,'--videos','--json'],capture_output=True,text=True,timeout=20)
try:
    ok=run('/move');assert ok.returncode==0,ok.stderr
    assert json.loads(ok.stdout)['media']['videos'][0]['url']==base+'/film.mp4'
    assert '[OK] HTTP 200' in ok.stderr
    fail=run('/missing');assert fail.returncode!=0 and 'HTTP 404' in fail.stderr
    fail=run('/binary');assert fail.returncode!=0 and 'not HTML' in fail.stderr
finally:
    server.shutdown();server.server_close()
PY
echo 'PASS: help, forms, flags, JSON, stdin, curl, redirects, errors'
