#!/usr/bin/env bash
# Tests granular filters and URL fetching via loopback-only HTTP.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
tool="$root/bash/bin/recon/extracthtmlinfo.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
echo '<!doctype html><html><head><title>Test</title></head><body><video src="/film.mp4"></video><img src="/x.png"><a href="/a">A</a></body></html>' > "$tmp/page.html"
bash "$tool" > "$tmp/help"
grep -q 'usage: extracthtmlinfo' "$tmp/help"
bash "$tool" "$tmp/page.html" --base-url https://example.org/ --videos --images --json --quiet > "$tmp/report.json"
python3 - "$tmp/report.json" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]))
assert list(r)==['media']
assert set(r['media'])=={'images','videos','video_sources'}
assert r['media']['videos'][0]['url']=='https://example.org/film.mp4'
PY
python3 - "$tool" <<'PY'
import json,subprocess,sys,threading
from http.server import BaseHTTPRequestHandler,HTTPServer
class H(BaseHTTPRequestHandler):
 def log_message(self,*a):pass
 def do_GET(self):
  if self.path=='/bad': self.send_error(404); return
  if self.path=='/redirect':
   self.send_response(302);self.send_header('Location','/ok');self.end_headers();return
  b=b'<!doctype html><html><body><video src="/watch.mp4"></video></body></html>'
  self.send_response(200);self.send_header('Content-Type','text/html');self.end_headers();self.wfile.write(b)
s=HTTPServer(('127.0.0.1',0),H)
threading.Thread(target=s.serve_forever,daemon=True).start()
try:
 base=f'http://127.0.0.1:{s.server_port}'
 good=subprocess.run(['bash',sys.argv[1],base+'/redirect','--videos','--json'],capture_output=True,text=True,timeout=20)
 assert good.returncode==0,good.stderr
 assert json.loads(good.stdout)['media']['videos'][0]['url']==base+'/watch.mp4'
 bad=subprocess.run(['bash',sys.argv[1],base+'/bad','--videos'],capture_output=True,text=True,timeout=20)
 assert bad.returncode!=0 and '404' in bad.stderr
finally:s.shutdown()
PY
echo 'PASS extracthtmlinfo granular filters, help, HTTP, redirects and errors'
