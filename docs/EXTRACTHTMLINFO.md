# extracthtmlinfo — HTML inventory CLI

A read-only HTML inspector installed from `bash/bin/recon/extracthtmlinfo.sh` into `~/.local/bin/extracthtmlinfo` by the normal dotfiles setup. Dependencies: Bash, Python 3 (stdlib); curl only when a URL is passed. No browser execution or linked resource downloads.

## Usage

```bash
extracthtmlinfo                                    # show help
extracthtmlinfo --help
extracthtmlinfo page.html                          # local file
extracthtmlinfo https://example.org/               # automatically fetch with curl
curl -fsSL https://example.org/ | extracthtmlinfo - --base-url https://example.org/
extracthtmlinfo https://example.org/ --videos --video-sources
extracthtmlinfo page.html --images --links --endpoints
extracthtmlinfo page.html --scripts --stylesheets --forms
extracthtmlinfo page.html --audio --subtitles --embeds --json
extracthtmlinfo page.html --sections summary,media --all
extracthtmlinfo https://example.org/ --timeout 10 --quiet
```

A URL invokes curl internally, following at most 5 redirects, with 8 MiB size cap, time limits, compressed transfer, 4xx/5xx handling, MIME checks, and origin of the effective URL used to resolve relative paths. `--json` writes only JSON to stdout; status/errors go to stderr. Without arguments the command prints help instead of blocking on stdin.

## Individual flags (combinable)

| Flag | Extracts |
| --- | --- |
| `--summary`, `--headings`, `--text`, `--links` | General information, headings, paragraphs, anchor URLs |
| `--images`, `--videos`, `--video-sources` | Images, HTML5 video, MP4/WebM/HLS/DASH candidates |
| `--blobs`, `--embeds`, `--audio`, `--subtitles`, `--media` | Blob URLs, iframes/media tags, audio, tracks, complete media |
| `--scripts`, `--stylesheets`, `--icons`, `--feeds`, `--assets` | External asset references |
| `--forms`, `--metadata`, `--jsonld` | Form names/types (no values), SEO/OpenGraph, JSON-LD |
| `--endpoints`, `--indicators`, `--discovery` | Candidate APIs and inline anti-debugging heuristics |

Other options: `--json`, `--sections LIST`, `--limit N`, `--all`, `--base-url URL`, `--no-color`, `--raw-urls`, `--timeout N`, `--quiet`. Individual flags can be combined with `--sections`.

## Error handling and limitations

Nonzero exit and stderr feedback on invalid arguments, missing local file, empty/non-HTML response, DNS/connect timeout, redirects or HTTP errors. Ctrl+C exits 130. URL fetching does not execute JavaScript or visit linked assets.

A `blob:` URL is a temporary in-browser object reference; it cannot be converted directly into a permanent HTTP URL. Only MP4/HLS/DASH references visible in downloaded HTML, metadata or inline scripts can be reported as candidates. No DRM or authentication bypass.

Sensitive-looking query parameters are redacted unless `--raw-urls` is set. Review output for other sensitive text before sharing.

## Test

```bash
bash -n bash/bin/recon/extracthtmlinfo.sh
bash tests/extracthtmlinfo-smoke.sh
```
