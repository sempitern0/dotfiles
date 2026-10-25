# extracthtmlinfo

Static, read-only HTML inspector at `bash/bin/recon/extracthtmlinfo.sh`. The existing workstation setup installs it as `~/.local/bin/extracthtmlinfo` (without the .sh extension).

**Requirements:** Bash and Python 3 standard library. No pip packages, linked-resource downloads, JS execution or browser automation.

## Usage

```bash
extracthtmlinfo                         # show help; no hang
extracthtmlinfo --help
extracthtmlinfo page.html
curl -fsSL --compressed https://example.org/ | extracthtmlinfo - --base-url https://example.org/
extracthtmlinfo page.html --sections summary,media,discovery --all
extracthtmlinfo page.html --json > report.json
extracthtmlinfo page.html --no-color --limit 20
```

Pretty-print mode displays separate tables for headings, link text and destinations, images, video elements, video streams/sources, embedded players, scripts, stylesheets, forms, metadata, JSON-LD types, candidate endpoints and inline JavaScript indicators. Output is terminal-width aware and colors are used only on interactive terminals. `--json` provides all records in machine-readable form.

Video discovery covers `<video>`, nested `<source>`, `<track>`, `<iframe>`, `og:video`, Twitter-player metadata, JSON-LD VideoObject (`contentUrl` and `embedUrl`), and simple direct media references (`.mp4`, `.webm`, `.m3u8`, `.mpd`) embedded in inline scripts. Results are candidates, not verified playable URLs.

**Important:** `blob:` URLs are browser-session-local object URLs, not remote file addresses and cannot be converted mathematically to stable HTTP(S) links. The command reports them separately; if underlying MP4/HLS/DASH URLs already appear in the downloaded HTML, it lists those as candidates. It cannot recover runtime-generated media or replace permissions, login, signed URLs or DRM.

Use `--base-url` to resolve relative paths from downloaded HTML. Inputs can be a local file or `-` for stdin; no live network URL is downloaded directly by the tool.

The parser does not print form field values, and redacts common sensitive URL query keys. It is not a comprehensive data-loss prevention tool: inspect generated reports before sharing them. Inputs are limited to 8 MiB.

Run tests using `bash tests/extracthtmlinfo-smoke.sh`.
