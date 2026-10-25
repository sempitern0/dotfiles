# extracthtmlinfo — inspect a downloaded HTML document

Read-only HTML inventory tool at `bash/bin/recon/extracthtmlinfo.sh`. The workstation setup automatically deploys it to `~/.local/bin/extracthtmlinfo` from its normal `bash/bin` discovery path.

**Requirements:** Bash and Python 3 (standard library). No packages from pip, network requests, JavaScript execution or browser automation.

## Examples

```bash
extracthtmlinfo index.html
extracthtmlinfo index.html --base-url https://example.org/app/
curl -fsSL --compressed https://example.org/ | extracthtmlinfo - --base-url https://example.org/
extracthtmlinfo index.html --sections summary,links,assets,discovery
extracthtmlinfo index.html --json > report.json
extracthtmlinfo index.html --limit 50
extracthtmlinfo index.html --all
```

Shows title, language, charset, description, canonical URL, headings, paragraphs, anchors, image/media references, script and stylesheet references, icon/feed links, form method/action and **field names/types only**, basic metadata and JSON-LD types. Additionally reports possible endpoints and inline-script anti-debugging indicators as *heuristics* rather than confirmed browser activity.

`--base-url` resolves relative URL references. Since HTML downloaded with curl does not always include the original address, this flag is recommended. By default the script reads **local files or stdin**, never a live URL. This is intentional: the user controls fetching with curl.

**Privacy:** common sensitive query keys (token, auth, password, etc.) are redacted in extracted URLs; values from forms are never printed. The tool is *not* a secret-scanner and arbitrary sensitive text in HTML or metadata may still appear in reports, so review before sharing outputs.

**Limits:** 8 MiB input; no external script parsing, browser DOM execution, XHR history, or automatic API fetching. This inventory does not prove the existence of an anti-debugging mechanism.

Test from the checkout with `bash tests/extracthtmlinfo-smoke.sh`.
