#!/usr/bin/env bash
# Profile Login Full - localhost browser-platform signal inspector
# Reports client-provided identity signals without modifying them.
set -Eeuo pipefail

WORK="$(mktemp -d)"
PROFILE_BASE="${XDG_CONFIG_HOME:-$HOME/.config}/profile-login-full"
mkdir -p "$PROFILE_BASE"
cleanup() {
  if [[ -n "${SERVER_PID:-}" ]]; then kill "$SERVER_PID" 2>/dev/null || true; fi
  rm -rf "$WORK"
}
trap cleanup EXIT

if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
  echo 'A graphical desktop session is required.' >&2
  exit 1
fi
command -v python3 >/dev/null || { echo 'Python 3 is required.' >&2; exit 1; }

cat > "$WORK/server.py" <<'PY'
import http.server
import json
import os
from pathlib import Path

HTML = r"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Browser Platform Signals — Local POC</title>
<style>body{font:16px system-ui,sans-serif;margin:2rem auto;max-width:850px;padding:0 1rem;color:#172033}
table{border-collapse:collapse;width:100%;table-layout:fixed}td,th{border-bottom:1px solid #ddd;padding:.8rem;text-align:left;overflow-wrap:anywhere}
th:first-child{width:35%}code{font:13px ui-monospace,monospace}small{color:#555}</style></head><body>
<h1>Browser Platform Signals</h1><p><strong>Local-only diagnostic.</strong> This page reports the browser's current signals without modifying or transmitting them to a remote service.</p>
<table><thead><tr><th>Signal</th><th>Observed value</th></tr></thead><tbody id="signals"></tbody></table>
<p><small>Client Hints may be unavailable in Firefox or depend on the browser/request context. Values here are not evidence of device compliance, enrollment, or trusted device identity.</small></p>
<script>
(async () => {
  const headers = await fetch('/inspect', {cache:'no-store'}).then(r=>r.json());
  const uaData = navigator.userAgentData;
  let hints = 'Not supported';
  if (uaData) {
    hints = JSON.stringify({platform:uaData.platform, mobile:uaData.mobile, brands:uaData.brands});
  }
  const values = [
    ['HTTP User-Agent', headers['user-agent'] ?? 'Not sent'],
    ['navigator.userAgent', navigator.userAgent],
    ['navigator.platform', navigator.platform || 'Unavailable'],
    ['navigator.userAgentData', hints],
    ['Sec-CH-UA-Platform', headers['sec-ch-ua-platform'] ?? 'Not sent']
  ];
  const body = document.getElementById('signals');
  for (const [name,value] of values) {
    const tr=document.createElement('tr');
    for(const item of [name,value]) {
      const td=document.createElement('td'); const c=document.createElement('code');
      c.textContent=item; td.appendChild(c); tr.appendChild(td);
    }
    body.appendChild(tr);
  }
})();
</script></body></html>"""

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/inspect':
            data = json.dumps({k.lower(): v for k,v in self.headers.items()}).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
        elif self.path in ('/', '/index.html'):
            data = HTML.encode()
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
        else:
            self.send_error(404)
            return
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)
    def log_message(self, *_args): pass

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
Path(os.environ['PORT_FILE']).write_text(str(server.server_port))
server.serve_forever()
PY

PORT_FILE="$WORK/port" python3 "$WORK/server.py" &
SERVER_PID=$!
for _ in {1..50}; do
  [[ -s "$WORK/port" ]] && break
  kill -0 "$SERVER_PID" 2>/dev/null || { echo "Local test server exited unexpectedly." >&2; exit 1; }
  sleep 0.1
done
[[ -s "$WORK/port" ]] || { echo 'Unable to start local server.' >&2; exit 1; }
URL="http://127.0.0.1:$(cat "$WORK/port")/"
echo "Local browser signal report: $URL"
echo '1) Firefox'
echo '2) Chrome / Chromium'
echo '3) Exit'
read -r -p 'Choose browser [1-3]: ' choice
case "$choice" in
  1)
    if command -v firefox >/dev/null 2>&1; then
      if command -v snap >/dev/null 2>&1 && snap list firefox >/dev/null 2>&1; then
        PROFILE="$HOME/snap/firefox/common/profile-login-full"
      else
        PROFILE="$PROFILE_BASE/firefox"
      fi
      mkdir -p "$PROFILE"
      firefox --no-remote --new-instance --profile "$PROFILE" "$URL"
    else
      echo 'Firefox not found.' >&2; exit 1
    fi
    ;;
  2)
    BROWSER=''
    for name in google-chrome google-chrome-stable chromium chromium-browser; do
      if command -v "$name" >/dev/null 2>&1; then BROWSER="$(command -v "$name")"; break; fi
    done
    [[ -n "$BROWSER" ]] || { echo 'Chrome/Chromium not found.' >&2; exit 1; }
    PROFILE="$PROFILE_BASE/chromium"
    if command -v snap >/dev/null 2>&1 && snap list chromium >/dev/null 2>&1 && [[ "$BROWSER" == *chromium* ]]; then
      PROFILE="$HOME/snap/chromium/common/profile-login-full"
    fi
    mkdir -p "$PROFILE"
    "$BROWSER" --user-data-dir="$PROFILE" --no-first-run "$URL"
    ;;
  3) exit 0 ;;
  *) echo 'Invalid choice.' >&2; exit 2 ;;
esac
