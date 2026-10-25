# extracthtmlinfo · Static HTML inspector

Inspect a local HTML file, URL, or a pipe. Uses **Bash + Python 3 standard library**, and `curl` only when a URL is passed. The existing dotfiles setup copies `bash/bin/recon/extracthtmlinfo.sh` to `~/.local/bin/extracthtmlinfo`.

## Start here

```bash
extracthtmlinfo                 # concise quick-start help
extracthtmlinfo --help          # complete flag reference
extracthtmlinfo page.html       # saved HTML
extracthtmlinfo https://example.org/  # curl under the hood
curl -fsSL https://example.org/ | extracthtmlinfo - --base-url https://example.org/
```

## Select information

Filters can be combined. When none is selected, the default overview is displayed.

| Topic | Individual switches |
|---|---|
| Page | `--summary` `--headings` `--text` `--links` |
| Media | `--images` `--videos` `--video-sources` `--blobs` `--embeds` `--audio` `--subtitles` |
| Assets | `--scripts` `--stylesheets` `--icons` `--feeds` |
| Data | `--forms` `--metadata` `--jsonld` |
| Recon | `--endpoints` `--indicators` |
| Broad groups | `--media` `--assets` `--discovery` `--sections summary,media` |

```bash
extracthtmlinfo page.html --links --images --json > report.json
extracthtmlinfo https://example.org/ --videos --video-sources
extracthtmlinfo page.html --scripts --endpoints --all
extracthtmlinfo page.html --no-color --limit 25
```

Use `--json` for machine-readable stdout (status/errors go to stderr), `--all` to disable the default 10-row display limit, `--timeout SEC` for downloads, and `--quiet` to suppress progress. Use `--base-url` to resolve relative URLs in saved files.

HTML is limited to 8 MiB and fetching to five redirects. The tool does not execute JS or request embedded resources. URLs beginning with `blob:` are browser-local and cannot be converted to public HTTP URLs; the tool only finds media source references visible in HTML. Forms report field **names/types only**, not submitted values. Query parameters likely to contain credentials are masked unless `--raw-urls` is set. Review all output before sharing.

## Validate

```bash
bash -n bash/bin/recon/extracthtmlinfo.sh
bash tests/extracthtmlinfo-smoke.sh
```
