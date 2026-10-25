#!/usr/bin/env bash
# Inspect local HTML without running JavaScript. Python 3 standard library only.
set -euo pipefail
command -v python3 >/dev/null || { echo 'extracthtmlinfo: python3 required' >&2; exit 1; }
exec python3 -c "$(cat <<'PY'
import argparse, json, os, re, sys
from html.parser import HTMLParser
from urllib.parse import urljoin, urlsplit, urlunsplit, parse_qsl, urlencode
MAX=8*1024*1024
SECTIONS=('summary','headings','text','links','media','assets','forms','metadata','discovery')
SECRET=re.compile(r'token|secret|password|passwd|api.?key|session|signature|auth|credential',re.I)
def tidy(v): return re.sub(r'\s+',' ',re.sub(r'[\x00-\x1f\x7f-\x9f]',' ',str(v or ''))).strip()
def dedup(items,key=lambda x:x):
    seen=set(); out=[]
    for x in items:
        k=key(x)
        if k not in seen: seen.add(k); out.append(x)
    return out
class Inspector(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.title=''; self.lang=''; self.base=''; self.charset=''
        self.metas=[]; self.headings=[]; self.text=[]; self.links=[]; self.images=[]; self.media=[]
        self.js=[]; self.css=[]; self.icons=[]; self.feeds=[]; self.forms=[]; self.jsonld=[]
        self.inline=[]; self.styles=0; self.active=None; self.stack=[]; self.script=None
    def handle_starttag(self,tag,attrs):
        d=dict(attrs)
        if tag=='html': self.lang=d.get('lang','')
        if tag=='base' and not self.base: self.base=d.get('href','')
        if tag=='meta':
            self.charset=d.get('charset',self.charset)
            name=d.get('name') or d.get('property') or d.get('http-equiv')
            if name and 'content' in d: self.metas.append({'name':tidy(name).lower(),'value':tidy(d['content'])})
        if tag=='link' and d.get('href'):
            rel=(d.get('rel') or '').lower(); item={'rel':rel,'url':d['href']}
            if 'stylesheet' in rel: self.css.append(item)
            if 'icon' in rel: self.icons.append(item)
            if 'alternate' in rel and d.get('type') in ('application/rss+xml','application/atom+xml'): self.feeds.append(item)
            if 'canonical' in rel: self.metas.append({'name':'canonical','value':d['href']})
        if tag=='img': self.images.append({'url':d.get('src') or d.get('data-src') or '','alt':tidy(d.get('alt'))})
        if tag in ('video','audio','iframe','source','track') and d.get('src'): self.media.append({'kind':tag,'url':d['src']})
        if tag=='form': self.forms.append({'method':(d.get('method') or 'GET').upper(),'action':d.get('action',''),'fields':[]})
        if tag in ('input','select','textarea') and self.forms and d.get('name'):
            self.forms[-1]['fields'].append({'name':d['name'],'type':d.get('type',tag)})
        if tag=='style': self.styles+=1
        if tag=='script': self.script={'url':d.get('src',''),'type':d.get('type',''),'parts':[]}
        if tag in ('title','p','a','h1','h2','h3','h4','h5','h6'):
            self.stack.append({'tag':tag,'url':d.get('href',''),'parts':[]})
    def handle_data(self,data):
        if self.script is not None: self.script['parts'].append(data); return
        if self.stack: self.stack[-1]['parts'].append(data)
    def handle_endtag(self,tag):
        if tag=='script' and self.script is not None:
            s=self.script; body=''.join(s['parts']); self.script=None
            if s['url']: self.js.append({'url':s['url'],'type':s['type']})
            elif s['type'].lower()=='application/ld+json':
                try:
                    o=json.loads(body); objects=o if isinstance(o,list) else [o]
                    for obj in objects:
                        if isinstance(obj,dict):
                            for node in obj.get('@graph',[obj]):
                                if isinstance(node,dict): self.jsonld.append({'type':node.get('@type','unknown')})
                except (ValueError,TypeError): pass
            elif body.strip(): self.inline.append(body)
        if self.stack and self.stack[-1]['tag']==tag:
            x=self.stack.pop(); txt=tidy(''.join(x['parts']))
            if tag=='title': self.title+=txt
            elif tag=='p' and txt: self.text.append(txt)
            elif tag=='a' and x['url']: self.links.append({'url':x['url'],'text':txt})
            elif tag.startswith('h') and len(tag)==2 and txt: self.headings.append({'level':tag.upper(),'text':txt})
            if self.stack: self.stack[-1]['parts'].append(txt)
def main():
    p=argparse.ArgumentParser(description='Static local HTML inventory; JavaScript is never executed.')
    p.add_argument('file',nargs='?',default='-',help='Local HTML or - (stdin)')
    p.add_argument('--base-url',default='',help='Base URL for resolving relative paths')
    p.add_argument('--json',action='store_true',help='Machine-readable JSON output')
    p.add_argument('--sections',default=','.join(SECTIONS),help='Comma-separated sections: '+','.join(SECTIONS))
    p.add_argument('--limit',type=int,default=12,help='Max displayed items per section')
    p.add_argument('--all',action='store_true',help='Display all items')
    p.add_argument('--no-color',action='store_true',help='Disable ANSI colors')
    a=p.parse_args()
    sections=[x.strip() for x in a.sections.split(',') if x.strip()]
    if not sections or any(x not in SECTIONS for x in sections): p.error('invalid --sections')
    if a.limit<1: p.error('--limit must be positive')
    if a.base_url and urlsplit(a.base_url).scheme not in ('http','https'): p.error('--base-url requires HTTP(S)')
    try:
        if a.file!='-' and os.path.getsize(a.file)>MAX: raise ValueError('input exceeds 8 MiB')
        with (open(a.file,'rb') if a.file!='-' else sys.stdin.buffer) as f: blob=f.read(MAX+1)
        if len(blob)>MAX: raise ValueError('input exceeds 8 MiB')
        header=blob[:4096].decode('ascii','ignore')
        match=re.search(r'charset\s*=\s*[\x22\x27]?([\w.-]+)',header,re.I)
        encoding=match.group(1) if match else 'utf-8-sig'
        try: data=blob.decode(encoding,errors='replace')
        except LookupError: data=blob.decode('utf-8-sig',errors='replace')
        h=Inspector(); h.feed(data); h.close()
    except (OSError,ValueError) as e:
        print('extracthtmlinfo: '+str(e),file=sys.stderr); return 1
    base=a.base_url or h.base
    def safe(v):
        value=urljoin(base,v) if base else v
        try:
            u=urlsplit(value); q=parse_qsl(u.query,keep_blank_values=True)
            return urlunsplit((u.scheme,u.netloc,u.path,urlencode([(k,'[REDACTED]' if SECRET.search(k) else val) for k,val in q]),u.fragment)) if u.query else value
        except ValueError: return value
    def norm(xs): return dedup([{**x,'url':safe(x['url'])} for x in xs if x['url']],lambda x:x['url'])
    links=norm(h.links); host=urlsplit(base).netloc.lower() if base else ''
    meta={x['name']:x['value'] for x in h.metas}
    result={
      'summary':{'source':a.file if a.file!='-' else 'stdin','title':tidy(h.title),'language':h.lang,'charset':h.charset or 'unspecified','base_url':base,'description':meta.get('description',''),'canonical':safe(meta.get('canonical',''))},
      'headings':h.headings,'text':dedup(h.text),
      'links':{'total':len(links),'internal':sum(bool(host) and urlsplit(x['url']).netloc.lower()==host for x in links),'items':links},
      'media':{'images':norm(h.images),'embedded':norm(h.media)},
      'assets':{'scripts':norm(h.js),'inline_scripts':len(h.inline),'stylesheets':norm(h.css),'inline_styles':h.styles,'icons':norm(h.icons),'feeds':norm(h.feeds)},
      'forms':[{'method':x['method'],'action':safe(x['action']) if x['action'] else '','fields':x['fields']} for x in h.forms],
      'metadata':{'meta':[{'name':x['name'],'value':safe(x['value']) if x['name'] in ('canonical','og:url','twitter:url') else x['value']} for x in h.metas],'json_ld':h.jsonld},
      'discovery':{'possible_endpoints':dedup([safe(x) for x in re.findall(r'[\x22\x27]((?:https?://[^\x22\x27\s<>]+|/(?:api/[^\x22\x27\s<>]+|graphql\b[^\x22\x27\s<>]*)))[\x22\x27]',data,re.I) if re.search(r'/api/|graphql|\.json',x,re.I)]),
                   'inline_js_indicators':[label for label,pattern in [('debugger','\\bdebugger\\s*;'),('devtools','\\bdevtools\\b'),('window.close','\\bwindow\\.close\\s*\\('),('window dimensions','\\bouterWidth\\b|\\binnerWidth\\b'),('redirect','\\blocation\\.(?:href|replace|assign)')] if re.search(pattern,'\n'.join(h.inline),re.I)],
                   'note':'Static heuristics; no external JavaScript or runtime API calls inspected.'}
    }
    result={key:result[key] for key in sections}
    if a.json: print(json.dumps(result,ensure_ascii=False,indent=2)); return 0
    def show(prefix,value):
        if isinstance(value,dict):
            for key,val in value.items(): show(prefix+' '+key if prefix else key,val)
        elif isinstance(value,list):
            print('  '+prefix+f' ({len(value)})')
            for entry in (value if a.all else value[:a.limit]):
                print('    - '+tidy(json.dumps(entry,ensure_ascii=False) if isinstance(entry,dict) else entry)[:300])
            if not a.all and len(value)>a.limit: print('    ... more: use --all or --limit N')
        elif value not in (None,''): print('  '+prefix+': '+tidy(value))
    print('HTML INFO: '+(a.file if a.file!='-' else 'stdin'))
    print('-'*60)
    for key,value in result.items():
        print('\n['+key.upper()+']')
        show('',value)
    return 0
try: sys.exit(main())
except BrokenPipeError: sys.exit(0)
PY
)" "$@"
