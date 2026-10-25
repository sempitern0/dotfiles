#!/usr/bin/env bash
# Static HTML inspection, using Python 3 standard library. Does not execute JS.
set -euo pipefail
if ! command -v python3 >/dev/null 2>&1; then
  printf 'extracthtmlinfo: Python 3 is required.\n' >&2
  exit 1
fi
exec python3 -c "$(cat <<'PY'
import argparse
import json
import os
import re
import shutil
import subprocess
import tempfile
import sys
import textwrap
from functools import lru_cache
from html.parser import HTMLParser
from urllib.parse import parse_qsl, urlencode, urljoin, urlsplit, urlunsplit

MAX_INPUT = 8 * 1024 * 1024
SECTIONS = ('summary', 'headings', 'text', 'links', 'media', 'assets', 'forms', 'metadata', 'discovery')
# One registry powers the filter selection and --help descriptions.
FILTER_GROUPS = {
    'Page and content': {
        'summary': ('summary', None, 'Site title, language, canonical and overview'),
        'headings': ('headings', None, 'H1–H6 headings'),
        'text': ('text', None, 'Visible paragraph text (static HTML)'),
        'links': ('links', None, 'Anchor text and destination URLs'),
    },
    'Images, video and audio': {
        'images': ('media', ('images',), 'Image URLs and alternate text'),
        'videos': ('media', ('videos', 'video_sources'), 'Video players and source candidates'),
        'video-sources': ('media', ('video_sources',), 'MP4, WebM, HLS and DASH candidates'),
        'blobs': ('media', ('blob_urls',), 'Temporary browser blob: references'),
        'embeds': ('media', ('embedded',), 'iframes and embedded media tags'),
        'audio': ('media', ('audio',), 'Audio elements and associated sources'),
        'subtitles': ('media', ('subtitles',), 'Caption/subtitle tracks'),
        'media': ('media', None, 'All media categories'),
    },
    'Assets and metadata': {
        'scripts': ('assets', ('scripts', 'inline_scripts'), 'External and inline script counts'),
        'stylesheets': ('assets', ('stylesheets', 'inline_styles'), 'External CSS and inline style counts'),
        'icons': ('assets', ('icons',), 'Icons and favicons'),
        'feeds': ('assets', ('feeds',), 'RSS/Atom feed references'),
        'assets': ('assets', None, 'All CSS/JS/icons/feeds'),
        'forms': ('forms', None, 'Form actions, methods and field names (no values)'),
        'metadata': ('metadata', ('meta',), 'SEO, Open Graph and Twitter metadata'),
        'jsonld': ('metadata', ('json_ld',), 'JSON-LD structured-data types'),
    },
    'Static discovery': {
        'endpoints': ('discovery', ('possible_endpoints',), 'Possible API endpoints in embedded scripts'),
        'indicators': ('discovery', ('inline_js_indicators',), 'Possible anti-debugging JavaScript indicators'),
        'discovery': ('discovery', None, 'All discovery results'),
    },
}
FILTERS = {flag: (section, keys)
           for group in FILTER_GROUPS.values()
           for flag, (section, keys, _description) in group.items()}

DEFAULT_SECTIONS = ('summary', 'headings', 'links', 'media', 'assets', 'forms', 'metadata', 'discovery')
SENSITIVE = re.compile(r'(?:token|secret|password|passwd|api[_-]?key|session|signature|auth|credential|access[_-]?key|jwt|code)', re.I)
VIDEO_EXT = re.compile(r'\.(?:mp4|m4v|webm|mov|ogv|m3u8|mpd)(?:$|[?#])', re.I)
INLINE_URLS = re.compile(r'[\x22\x27]((?:https?://|/)[^\x22\x27\s<>]{1,2000})[\x22\x27]', re.I)
VIDEO_HOST = re.compile(r'(?:youtube(?:-nocookie)?\.com|youtu\.be|vimeo\.com|dailymotion\.com|player\.twitch\.tv)', re.I)

_WHITESPACE = re.compile(r'\s+')
_CONTROL = re.compile(r'[\x00-\x1f\x7f-\x9f]')

def clean(value):
    return _WHITESPACE.sub(' ', _CONTROL.sub(' ', str(value or ''))).strip()

def unique(values, key=lambda x: x):
    seen, result = set(), []
    for item in values:
        marker = key(item)
        if marker not in seen:
            seen.add(marker)
            result.append(item)
    return result

class Page(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.title = ''; self.lang = ''; self.charset = ''; self.base = ''
        self.metas = []; self.headings = []; self.text = []; self.links = []
        self.images = []; self.embedded = []; self.videos = []; self.audios = []; self.subtitles = []; self.video_sources = []
        self.blobs = []; self.js = []; self.css = []; self.icons = []; self.feeds = []
        self.forms = []; self.active_form = None
        self.jsonld = []; self.inline = []; self.inline_styles = 0
        self.script = None; self.captures = []; self.media_stack = []

    def handle_starttag(self, tag, attrs):
        d = dict(attrs)
        if tag == 'html': self.lang = d.get('lang', '')
        if tag == 'base' and not self.base: self.base = d.get('href', '')
        if tag == 'meta':
            self.charset = d.get('charset', self.charset)
            name = d.get('name') or d.get('property') or d.get('http-equiv')
            if name and 'content' in d:
                self.metas.append({'name': clean(name).lower(), 'value': clean(d['content'])})
        if tag == 'link' and d.get('href'):
            item = {'rel': (d.get('rel') or '').lower(), 'url': d['href']}
            if 'stylesheet' in item['rel']: self.css.append(item)
            if 'icon' in item['rel']: self.icons.append(item)
            if 'alternate' in item['rel'] and d.get('type') in ('application/rss+xml', 'application/atom+xml'): self.feeds.append(item)
            if 'canonical' in item['rel']: self.metas.append({'name': 'canonical', 'value': d['href']})
        if tag == 'img':
            src = d.get('src') or d.get('data-src')
            if src: self.images.append({'url': src, 'alt': clean(d.get('alt'))})
        if tag == 'form':
            self.active_form = {'method': (d.get('method') or 'GET').upper(), 'action': d.get('action',''), 'fields': []}
            self.forms.append(self.active_form)
        if tag in ('input', 'select', 'textarea') and self.active_form is not None and d.get('name'):
            self.active_form['fields'].append({'name': d['name'], 'type': d.get('type', tag)})
        if tag == 'style': self.inline_styles += 1
        if tag == 'script': self.script = {'url': d.get('src', ''), 'type': d.get('type',''), 'parts': []}
        if tag in ('title', 'p', 'a', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6'):
            self.captures.append({'tag': tag, 'url': d.get('href',''), 'parts': []})
        if tag in ('video', 'audio'):
            entry = {'kind': tag, 'url': d.get('src') or d.get('data-src') or '',
                     'poster': d.get('poster', ''), 'sources': [], 'tracks': []}
            if tag == 'video': self.videos.append(entry)
            else: self.audios.append(entry)
            self.media_stack.append(entry)
            if entry['url']:
                self.embedded.append({'kind': tag, 'url': entry['url']})
                if tag == 'video' and not entry['url'].startswith('blob:'):
                    self.video_sources.append({'origin': 'video[src]', 'url': entry['url']})
            if tag == 'video':
                for field in ('data-video-src','data-hls-src','data-dash-src','data-mp4'):
                    if d.get(field): self.video_sources.append({'origin': field, 'url': d[field]})
        if tag == 'source':
            src = d.get('src') or d.get('data-src')
            if src:
                item = {'url': src, 'type': d.get('type','')}
                if self.media_stack:
                    self.media_stack[-1]['sources'].append(item)
                    kind = self.media_stack[-1]['kind']
                else: kind = 'source'
                self.embedded.append({'kind': kind + '/source', 'url': src})
                if kind != 'audio' and (kind == 'video' or VIDEO_EXT.search(src) or 'video/' in item['type']):
                    self.video_sources.append({'origin': 'source', 'url': src, 'type': item['type']})
        if tag == 'track' and d.get('src'):
            track = {'url': d['src'], 'kind': d.get('kind',''), 'lang': d.get('srclang','')}
            self.subtitles.append(track)
            if self.media_stack: self.media_stack[-1]['tracks'].append(track)
            self.embedded.append({'kind':'track','url':d['src']})
        if tag == 'iframe':
            src = d.get('src') or d.get('data-src')
            if src:
                self.embedded.append({'kind': 'iframe', 'url': src})
                if VIDEO_HOST.search(src): self.video_sources.append({'origin':'video iframe','url':src})
        for k,v in d.items():
            if k in ('data-video-url','data-stream-url','data-hls','data-dash','data-file','data-video','data-src') and isinstance(v,str) and VIDEO_EXT.search(urlsplit(v).path):
                self.video_sources.append({'origin': tag+'['+k+']', 'url':v})
            if v and isinstance(v,str) and v.startswith('blob:'):
                self.blobs.append({'origin': tag+'['+k+']', 'url':v})

    def handle_data(self, data):
        if self.script is not None: self.script['parts'].append(data); return
        if self.captures: self.captures[-1]['parts'].append(data)

    def handle_endtag(self, tag):
        if tag == 'form': self.active_form = None
        if tag == 'script' and self.script is not None:
            s = self.script; self.script = None; body = ''.join(s['parts'])
            if s['url']: self.js.append({'url': s['url'], 'type': s['type']})
            elif s['type'].lower() == 'application/ld+json':
                try:
                    raw = json.loads(body)
                    def walk(obj):
                        if isinstance(obj, list):
                            for x in obj: walk(x)
                        elif isinstance(obj, dict):
                            self.jsonld.append({'type': obj.get('@type','unknown')}) if '@type' in obj else None
                            kinds = obj.get('@type', [])
                            if isinstance(kinds,str): kinds = [kinds]
                            if 'VideoObject' in kinds:
                                for name in ('contentUrl','embedUrl'):
                                    if isinstance(obj.get(name),str):
                                        self.video_sources.append({'origin':'JSON-LD '+name,'url':obj[name]})
                            if '@graph' in obj: walk(obj['@graph'])
                    walk(raw)
                except (ValueError, TypeError): pass
            elif body.strip(): self.inline.append(body)
        if tag in ('video','audio') and self.media_stack and self.media_stack[-1]['kind'] == tag:
            self.media_stack.pop()
        if self.captures and self.captures[-1]['tag'] == tag:
            item = self.captures.pop(); value = clean(''.join(item['parts']))
            if tag == 'title': self.title += value
            elif tag == 'p' and value: self.text.append(value)
            elif tag == 'a' and item['url']: self.links.append({'url': item['url'], 'text': value})
            elif tag in ('h1','h2','h3','h4','h5','h6') and value:
                self.headings.append({'level':tag.upper(),'text':value})
            if self.captures: self.captures[-1]['parts'].append(value)

def fetch_url(url, timeout):
    """Fetch one HTML document; no additional URLs/resources are requested."""
    if not shutil.which('curl'):
        raise ValueError('curl is required to fetch URLs. Install curl or pass a downloaded HTML file.')
    try:
        parsed = urlsplit(url)
        if parsed.scheme not in ('http','https') or not parsed.netloc or not parsed.hostname:
            raise ValueError('URL must start with http:// or https:// and include a host')
    except ValueError as exc:
        raise ValueError('Invalid URL: ' + str(exc)) from exc
    with tempfile.TemporaryDirectory(prefix='extracthtmlinfo-') as tmp:
        out = os.path.join(tmp,'page.html')
        cmd = ['curl','--silent','--show-error','--location','--fail',
               '--max-redirs','5','--compressed',
               '--connect-timeout',str(min(timeout,10)), '--max-time',str(timeout),
               '--max-filesize',str(MAX_INPUT),
               '--proto','=http,https','--proto-redir','=http,https',
               '--output',out,'--write-out','%{http_code}\n%{url_effective}\n%{content_type}', url]
        try:
            proc = subprocess.run(cmd,stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE,text=True,timeout=timeout+4,check=False)
        except subprocess.TimeoutExpired as exc:
            raise ValueError(f'Network timeout after {timeout}s. Check connectivity or use --timeout N.') from exc
        fields = proc.stdout.splitlines()
        code = fields[0] if fields else '000'
        effective = fields[1] if len(fields)>1 and fields[1] else url
        ctype = fields[2] if len(fields)>2 else ''
        if proc.returncode:
            reason = proc.stderr.strip() or 'unknown curl error'
            if code.isdigit() and int(code)>=400:
                raise ValueError(f'HTTP {code} for {effective}: {reason}')
            if proc.returncode==63:
                raise ValueError('Downloaded HTML exceeds the 8 MiB limit (curl error 63).')
            raise ValueError(f'Unable to fetch {url} (curl exit {proc.returncode}): {reason}')
        if not code.isdigit() or not 200<=int(code)<300:
            raise ValueError(f'Unexpected HTTP status {code} for {effective}')
        if ctype and not any(ctype.lower().split(';')[0].strip()==kind for kind in
                             ('text/html','application/xhtml+xml','text/plain','application/xml','text/xml')):
            raise ValueError(f'Response is not HTML (Content-Type: {ctype}).')
        with open(out,'rb') as f: payload = f.read(MAX_INPUT+1)
        if len(payload)>MAX_INPUT: raise ValueError('Downloaded HTML exceeds the 8 MiB limit.')
        if not payload: raise ValueError(f'Empty HTTP response from {effective}.')
    return payload, effective, code, ctype

EXAMPLES = '''Examples:
  extracthtmlinfo                               Quick start (this panel)
  extracthtmlinfo --help                        Detailed options
  extracthtmlinfo page.html                     Analyze a saved file
  extracthtmlinfo https://example.org/          Download HTML via curl, then analyze
  curl -fsSL https://example.org/ | extracthtmlinfo - --base-url https://example.org/
  extracthtmlinfo page.html --images --links    Combine filters
  extracthtmlinfo https://example.org/ --videos --video-sources
  extracthtmlinfo page.html --endpoints --json > endpoints.json
  extracthtmlinfo page.html --sections summary,media --all

Notes:
  - URL input uses curl; only the HTML document is downloaded.
  - Relative links are resolved with the fetched URL or --base-url.
  - JSON goes to stdout; fetch status and errors go to stderr.
  - A blob: URL is not a directly downloadable media link.
  - This tool never executes JavaScript or bypasses access controls.'''

QUICK_HELP = '''usage: extracthtmlinfo <file.html | http(s)://URL | -> [options]

Extract important information from static HTML in readable tables or JSON.

INPUT
  file.html                 Read a downloaded HTML file
  https://example.org/      Fetch the HTML with curl (no browser required)
  -                         Read HTML from stdin (pipe)

QUICK EXAMPLES
  extracthtmlinfo https://example.org/ --links
  extracthtmlinfo index.html --images --videos
  curl -fsSL https://example.org | extracthtmlinfo - --base-url https://example.org/
  extracthtmlinfo index.html --endpoints --json > report.json

FILTERS (combine as needed)
  Content    --summary --headings --text --links
  Media      --images --videos --video-sources --audio --subtitles --blobs --embeds
  Assets     --scripts --stylesheets --icons --feeds
  Other      --forms --metadata --jsonld --endpoints --indicators
  Groups     --media --assets --discovery or --sections summary,media

OUTPUT       --json  --all  --limit N  --no-color
FETCH        --timeout N  --base-url URL  --quiet
PRIVACY      --raw-urls  (disable automatic URL parameter redaction)

Run 'extracthtmlinfo --help' for every option and more examples.
'''

def cli():
    parser = argparse.ArgumentParser(
        prog='extracthtmlinfo',
        description='Inspect a local HTML file, stdin or a web URL without executing JavaScript.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=EXAMPLES,
    )
    parser.add_argument('file', nargs='?', metavar='FILE|URL|-',
                        help='HTML path, http(s) URL, or - for stdin (a pipe)')
    output = parser.add_argument_group('Display and selection')
    output.add_argument('--json', action='store_true', help='JSON to stdout; good for jq and scripts')
    output.add_argument('--sections', metavar='NAMES',
                        help='Select main groups (comma-separated); see examples below')
    output.add_argument('--limit', type=int, default=10, metavar='N',
                        help='Maximum rows shown per table (default 10)')
    output.add_argument('--all', action='store_true', help='Display all rows, ignoring --limit')
    output.add_argument('--no-color', action='store_true', help='Disable ANSI colors in terminal')
    output.add_argument('--raw-urls', action='store_true',
                        help='Disable URL query-parameter redaction; may expose secrets')
    network = parser.add_argument_group('Fetching URLs (curl)')
    network.add_argument('--base-url', default='', metavar='URL',
                         help='Resolve relative URLs when reading a file or stdin')
    network.add_argument('--timeout', type=int, default=25, metavar='SEC',
                         help='Overall network timeout (1–120 seconds, default 25)')
    network.add_argument('--quiet', action='store_true',
                         help='Hide progress on stderr; errors still appear')
    for label, filters in FILTER_GROUPS.items():
        group = parser.add_argument_group(label+' filters (combine multiple flags)')
        for flag, (_section, _fields, description) in filters.items():
            group.add_argument('--'+flag, action='store_true',
                               dest='only_'+flag.replace('-','_'), help=description)
    if len(sys.argv) == 1:
        print(QUICK_HELP, end='')
        return 0
    args = parser.parse_args()
    if args.file is None:
        parser.error('missing FILE or URL. Example: extracthtmlinfo https://example.org/ (or run without arguments for help)')
    if args.file == '-' and sys.stdin.isatty():
        parser.error('stdin is a terminal; provide a file or URL, or pipe HTML into -')
    if args.limit<1: parser.error('--limit must be >= 1')
    if not 1<=args.timeout<=120: parser.error('--timeout must be between 1 and 120 seconds')
    if args.base_url and (urlsplit(args.base_url).scheme not in ('http','https') or not urlsplit(args.base_url).hostname):
        parser.error('--base-url requires a valid http(s) URL')
    selection={}
    def select(group, keys=None):
        if group not in selection or keys is None:
            selection[group]=None if keys is None else set(keys)
        elif selection[group] is not None:
            selection[group].update(keys)
    if args.sections is not None:
        names=[x.strip() for x in args.sections.split(',') if x.strip()]
        if not names or any(x not in SECTIONS for x in names): parser.error('invalid --sections value; see --help')
        for name in names: select(name)
    active=[flag for flag in FILTERS if getattr(args,'only_'+flag.replace('-','_'))]
    for flag in active: select(*FILTERS[flag])
    if not selection:
        for name in DEFAULT_SECTIONS: select(name)
    selected=[name for name in SECTIONS if name in selection]
    remote=args.file.lower().startswith(('http://','https://'))
    status=None
    try:
        if remote:
            if not args.quiet: print(f'[INFO] GET {args.file} (timeout {args.timeout}s; limit 8 MiB)',file=sys.stderr)
            payload, final_url, http_code, content_type = fetch_url(args.file,args.timeout)
            status={'requested_url':args.file,'http_status':http_code,'effective_url':final_url,
                    'content_type':content_type,'bytes':len(payload)}
            if not args.quiet: print(f'[OK] HTTP {http_code} • {len(payload)} bytes • {final_url}',file=sys.stderr)
        else:
            if '://' in args.file: raise ValueError('Unsupported URL scheme. Only http:// and https:// are allowed.')
            if args.file!='-' and os.path.getsize(args.file)>MAX_INPUT:
                raise ValueError('HTML file exceeds 8 MiB.')
            with (open(args.file,'rb') if args.file!='-' else sys.stdin.buffer) as f:
                payload=f.read(MAX_INPUT+1)
            if len(payload)>MAX_INPUT: raise ValueError('HTML input exceeds 8 MiB.')
            if not payload: raise ValueError('Empty HTML input. Check the file or curl pipeline.')
            final_url=args.base_url
            if not args.quiet and args.file!='-':
                print(f'[OK] Read {len(payload)} bytes from {args.file}',file=sys.stderr)
        if not re.search(rb'<(?:!doctype\s+html|html\b|[a-z][a-z0-9:-]*\b[^>]*>)',payload,re.I):
            raise ValueError('Input does not look like HTML. Check the URL or source file.')
        encoding = re.search(r'charset\s*=\s*[\x22\x27]?([\w.-]+)',payload[:4096].decode('ascii','ignore'),re.I)
        try: html = payload.decode(encoding.group(1) if encoding else 'utf-8-sig','replace')
        except LookupError: html = payload.decode('utf-8-sig','replace')
        page=Page(); page.feed(html); page.close()
    except (OSError,ValueError,UnicodeError) as exc:
        print('[ERROR] extracthtmlinfo: '+str(exc),file=sys.stderr)
        print('[HINT] Try extracthtmlinfo --help for examples.',file=sys.stderr)
        return 1
    base = urljoin(final_url,page.base) if page.base and final_url else page.base or final_url
    @lru_cache(maxsize=4096)
    def safe(url):
        if not url: return ''
        url = urljoin(base,url) if base else url
        if args.raw_urls: return url
        try:
            u = urlsplit(url)
            if not u.query: return url
            return urlunsplit((u.scheme,u.netloc,u.path,urlencode([(k,'[REDACTED]' if SENSITIVE.search(k) else v) for k,v in parse_qsl(u.query,keep_blank_values=True)]),u.fragment))
        except ValueError: return url
    def normalize(items, key=('url',)):
        normalized=[]
        for x in items:
            y={k:(safe(v) if k in ('url','poster') else v) for k,v in x.items()}
            if y.get('url'): normalized.append(y)
        return unique(normalized,lambda v: tuple(v.get(k,'') for k in key))
    def video_item(x):
        return {'kind':x['kind'], 'url':safe(x['url']), 'poster':safe(x['poster']),
                'sources':normalize(x['sources']),
                'tracks':[{**item,'url':safe(item['url'])} for item in x['tracks']]}
    meta = {x['name']:x['value'] for x in page.metas}
    for name in ('og:video','og:video:url','og:video:secure_url','twitter:player','twitter:player:stream'):
        for item in page.metas:
            if item['name'] == name and item['value']:
                page.video_sources.append({'origin':name,'url':item['value']})
    for link in page.links:
        if VIDEO_EXT.search(urlsplit(link['url']).path):
            page.video_sources.append({'origin':'anchor','url':link['url']})
    inline = '\n'.join(page.inline)
    inline_urls = [match.group(1).replace('\\/','/') for match in INLINE_URLS.finditer(inline)]
    for url in inline_urls:
        if VIDEO_EXT.search(urlsplit(url).path):
            page.video_sources.append({'origin':'inline script (candidate)','url':url})
        if url.startswith('blob:'):
            page.blobs.append({'origin':'inline script','url':url})
    for m in page.metas:
        if 'video' in m['name'] and m['value'].startswith('blob:'):
            page.blobs.append({'origin':m['name'],'url':m['value']})
    links=normalize(page.links)
    hostname=(urlsplit(base).hostname or '').removeprefix('www.')
    summary={'source':args.file,'title':clean(page.title),'language':page.lang,
             'charset':page.charset or (encoding.group(1) if encoding else 'unspecified'),
             'base_url':base,'description':meta.get('description',''),
             'canonical':safe(meta.get('canonical','')),
             'counts':{'headings':len(page.headings),'links':len(links),'images':len(page.images),
                       'videos':len(page.videos),'video_sources':len(normalize(page.video_sources,('url',))),
                       'scripts':len(page.js),'forms':len(page.forms)}}
    indicators=[label for label,pattern in [('debugger',r'\bdebugger\s*;'),('devtools',r'\bdevtools\b'),('window.close',r'\bwindow\.close\s*\('),('window dimensions',r'\b(?:outerWidth|innerWidth)\b'),('redirect',r'\blocation\.(?:href|replace|assign)'),('browser blobs',r'\b(?:createObjectURL|MediaSource)\b')] if re.search(pattern,inline,re.I)]
    candidates=[]
    for url in inline_urls:
        if re.search(r'/api/|/graphql(?:[/?#]|$)|\.json(?:[?#]|$)',url,re.I):
            candidates.append(safe(url))
    result={
        'summary':summary,
        'headings':page.headings,
        'text':unique(page.text),
        'links':{'total':len(links),'internal':sum((urlsplit(x['url']).hostname or '').removeprefix('www.')==hostname for x in links) if hostname else 0,'items':links},
        'media':{'images':normalize(page.images), 'embedded':normalize(page.embedded,('kind','url')),
                 'videos':[video_item(x) for x in page.videos],
                 'video_sources':normalize(page.video_sources,('url',)),
                 'blob_urls':unique([{'origin':x['origin'],'url':x['url']} for x in page.blobs],lambda x:x['url']),
                 'note':'blob: values identify temporary browser objects, not transferable download links.'},
        'assets':{'scripts':normalize(page.js), 'inline_scripts':len(page.inline),
                  'stylesheets':normalize(page.css), 'inline_styles':page.inline_styles,
                  'icons':normalize(page.icons), 'feeds':normalize(page.feeds)},
        'forms':[{'method':x['method'],'action':safe(x['action']), 'fields':x['fields']} for x in page.forms],
        'metadata':{'meta':[{**x,'value':safe(x['value']) if x['name'] in ('canonical','og:url','twitter:url','og:video','og:video:url','og:video:secure_url','twitter:player','twitter:player:stream') else x['value']} for x in page.metas],
                    'json_ld':unique(page.jsonld,lambda x:str(x.get('type')))},
        'discovery':{'possible_endpoints':unique(candidates), 'inline_js_indicators':indicators,
                     'note':'Heuristic static extraction only; scripts loaded externally and browser network requests are not inspected.'}}
    result={k:result[k] for k in selected}
    if args.json:
        print(json.dumps(result,ensure_ascii=False,indent=2)); return 0
    color=sys.stdout.isatty() and not args.no_color and 'NO_COLOR' not in os.environ
    def tint(s,num): return f'\033[{num}m{s}\033[0m' if color else s
    width=min(120,max(60,shutil.get_terminal_size((100,20)).columns))
    def section(name):
        print('\n'+tint('  '+name.upper()+'  ','1;36'))
        print('  '+'─'*(width-4))
    def value(label,v):
        if v is None or v=='': return
        prefix=f'  {label:<15} '
        lines=textwrap.wrap(clean(v),width=max(12,width-len(prefix)),break_long_words=True,break_on_hyphens=False) or ['']
        print(tint(prefix,'2')+lines[0]);
        for line in lines[1:]: print(' '*len(prefix)+line)
    def table(title,columns,rows):
        if not rows:
            print('  '+title+': —'); return
        visible=rows if args.all else rows[:args.limit]
        print('  '+tint(f'{title} ({len(rows)})','1'))
        maxw=width-4
        # Columns contain (header, width fraction); priority to URL/text fields
        weights=[p for h,p in columns]; available=maxw-3*(len(columns)-1)
        baseline = 7 * len(columns)
        extra = max(0, available - baseline)
        colw = [7 + extra * w // sum(weights) for w in weights]
        colw[-1] += available - sum(colw)
        heads=' | '.join(h[:n].ljust(n) for (h,_),n in zip(columns,colw))
        print('  '+tint(heads,'1'))
        print('  '+'-+-'.join('-'*n for n in colw))
        for raw in visible:
            vals=[clean(x) for x in raw]
            wrapped=[textwrap.wrap(s, width=n,break_long_words=True,break_on_hyphens=False) or [''] for s,n in zip(vals,colw)]
            for j in range(max(map(len,wrapped))):
                print('  '+' | '.join((lines[j] if j<len(lines) else '').ljust(n) for lines,n in zip(wrapped,colw)).rstrip())
        if len(visible)<len(rows): print('  '+tint(f'... {len(rows)-len(visible)} more; --all or --limit N','2'))
    print(tint('  EXTRACTHTMLINFO  ','1;35')+tint(' • static HTML inventory','2'))
    print('  '+('═'*(width-4)))
    for name in selected:
        d=result[name]; section(name)
        if name=='summary':
            for k,v in d.items():
                if k=='counts': table('Page overview',[('Item',2),('Count',1)],[(k,str(v)) for k,v in d['counts'].items()])
                else: value(k,v)
        elif name=='headings': table('Headings',[('Level',1),('Heading',6)],[(x['level'],x['text']) for x in d])
        elif name=='text': table('Paragraphs',[('Text',1)],[(x,) for x in d])
        elif name=='links':
            value('total',d['total']);value('internal',d['internal'])
            table('Links',[('Text',2),('URL',5)],[(x['text'],x['url']) for x in d['items']])
        elif name=='media':
            table('Images',[('Alt',2),('URL',5)],[(x.get('alt',''),x['url']) for x in d['images']])
            table('Video elements',[('Kind',1),('URL',3),('Poster',2)],[(x['kind'],x['url'] or '(child sources)',x['poster']) for x in d['videos']])
            table('Video streams / sources',[('Origin',2),('URL',5)],[(x['origin'],x['url']) for x in d['video_sources']])
            table('Embeds and media tags',[('Tag',1),('URL',5)],[(x['kind'],x['url']) for x in d['embedded']])
            table('Browser-only blob URLs',[('Origin',2),('URL',5)],[(x['origin'],x['url']) for x in d['blob_urls']])
            if d['blob_urls']: value('Caution',d['note'])
        elif name=='assets':
            value('Inline scripts',d['inline_scripts']);value('Inline styles',d['inline_styles'])
            for key in ('scripts','stylesheets','icons','feeds'):
                table(key.capitalize(),[('Type',2),('URL',5)],[(x.get('type') or x.get('rel') or '',x['url']) for x in d[key]])
        elif name=='forms':
            table('Forms',[('Method',1),('Action',4),('Fields (names only)',3)],[(x['method'],x['action'],', '.join(z['name']+'('+z['type']+')' for z in x['fields'])) for x in d])
        elif name=='metadata':
            table('Metadata',[('Key',2),('Value',5)],[(x['name'],x['value']) for x in d['meta']])
            table('JSON-LD types',[('Type',1)],[(str(x['type']),) for x in d['json_ld']])
        elif name=='discovery':
            table('Possible endpoints',[('URL',1)],[(x,) for x in d['possible_endpoints']])
            table('Script indicators',[('Indicator',1)],[(x,) for x in d['inline_js_indicators']])
            value('Scope',d['note'])
    return 0

try: sys.exit(cli())
except BrokenPipeError: sys.exit(0)
PY
)" "$@"