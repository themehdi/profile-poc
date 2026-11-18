#!/usr/bin/env bash
# Profile Login Full - localhost Android signal override POC
# Applies JavaScript-only overrides on this local test origin; reports real HTTP headers separately.
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
<title>Android Platform Simulation — Local POC</title>
<style>
body{font:15px system-ui,sans-serif;max-width:1100px;margin:2rem auto;padding:0 1rem;color:#202938;background:#fafbfd}
h1{font-size:1.65rem}table{border-collapse:collapse;width:100%;table-layout:fixed;background:white}
th,td{border:1px solid #dfe4ed;text-align:left;padding:.7rem;overflow-wrap:anywhere;vertical-align:top}
th:nth-child(1){width:20%}th:nth-child(2){width:37%}th:nth-child(3){width:37%}
code{font-size:12px}button{border:1px solid #9caaba;background:white;border-radius:6px;padding:.65rem 1rem;cursor:pointer}
.note{background:#edf2fa;padding:1rem;border-radius:8px}.muted{color:#586477}.ok{color:#16653e}.different{color:#9b4c00}
</style></head><body>
<h1>Android platform signal override POC — localhost only</h1>
<p class="note"><strong>Scope:</strong> this page applies JavaScript property overrides only within this local test page. It does not alter browser-wide identity, HTTP request headers, Client Hints, device registration, or sign-in trust. No data is transmitted outside localhost.</p>
<p>Test profile: Android 14 · Samsung SM-S918W · Chrome 131 Mobile (test values)</p>
<table><thead><tr><th>Signal</th><th>Observed in browser</th><th>Simulated Android value</th></tr></thead><tbody id="signals"><tr><td colspan="3">Reading local browser signals…</td></tr></tbody></table>
<p id="summary" class="muted"></p><button id="export" type="button" disabled>Download local JSON evidence</button>
<p class="muted">Firefox may not expose User-Agent Client Hints. The JavaScript values are page-local test overrides, not proof of Android hardware, Intune compliance, Entra registration, or trusted device identity. The server records the actual HTTP headers received.</p>
<script>
(async () => {
  const androidUA = 'Mozilla/5.0 (Linux; Android 14; SM-S918W) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';
  const expected = {
    'HTTP User-Agent':androidUA,
    'navigator.userAgent':androidUA,
    'navigator.platform':'Linux armv8l',
    'navigator.userAgentData':JSON.stringify({platform:'Android',mobile:true,brands:[{brand:'Google Chrome',version:'131'},{brand:'Chromium',version:'131'}]}),
    'Sec-CH-UA-Platform':'"Android"'
  };
  const overrideResults={};
  const testUAData = {
    platform:'Android', mobile:true,
    brands:[{brand:'Google Chrome',version:'131'},{brand:'Chromium',version:'131'}],
    getHighEntropyValues:async (hints)=>{
      const values={platform:'Android',platformVersion:'14.0.0',architecture:'arm',model:'SM-S918W',bitness:'64',fullVersionList:[{brand:'Google Chrome',version:'131.0.0.0'},{brand:'Chromium',version:'131.0.0.0'}]};
      return Object.fromEntries(hints.filter(k=>k in values).map(k=>[k,values[k]]));
    }
  };
  for (const [key,value] of Object.entries({userAgent:androidUA,platform:'Linux armv8l',userAgentData:testUAData})) {
    try {
      Object.defineProperty(navigator,key,{configurable:true,get:()=>value});
      overrideResults[key]='applied on this localhost page';
    } catch(e) {
      overrideResults[key]='not applied: '+String(e);
    }
  }
  try {
    const headers=await fetch('/inspect',{cache:'no-store'}).then(r=>r.json());
    const uaData=navigator.userAgentData;
    let uaDetail='Not supported';
    if (uaData) {
      const basic={platform:uaData.platform,mobile:uaData.mobile,brands:uaData.brands};
      try {
        const high=await uaData.getHighEntropyValues(['platformVersion','architecture','model','bitness','fullVersionList']);
        uaDetail=JSON.stringify({basic,highEntropy:high});
      } catch(e) {
        uaDetail=JSON.stringify({basic,highEntropyError:String(e)});
      }
    }
    const observed={
      'HTTP User-Agent':headers['user-agent']??'Not sent',
      'navigator.userAgent':navigator.userAgent,
      'navigator.platform':navigator.platform||'Unavailable',
      'navigator.userAgentData':uaDetail,
      'Sec-CH-UA-Platform':headers['sec-ch-ua-platform']??'Not sent'
    };
    const body=document.getElementById('signals');
    body.textContent='';
    for(const name of Object.keys(expected)){
      const tr=document.createElement('tr');
      for(const value of [name,observed[name],expected[name]]){
        const td=document.createElement('td');const code=document.createElement('code');
        code.textContent=value;td.appendChild(code);tr.appendChild(td);
      }
      body.appendChild(tr);
    }
    const unsupported=Object.values(observed).filter(v=>v==='Not supported'||v==='Not sent').length;
    document.getElementById('summary').textContent='Page-local override results: '+JSON.stringify(overrideResults)+'. HTTP User-Agent and Sec-CH-UA-Platform are measured from the actual request and are not modified by this page. '+unsupported+' signal(s) unavailable or not transmitted.';
    document.getElementById('export').disabled=false;
    document.getElementById('export').addEventListener('click',()=>{
      const evidence={test:'Android platform signal override POC',mode:'JavaScript overrides scoped to this localhost page only; HTTP headers unchanged',timestamp:new Date().toISOString(),target:'Android 14 SM-S918W Chrome 131 Mobile test profile',overrideResults,observed,expected};
      const blob=new Blob([JSON.stringify(evidence,null,2)],{type:'application/json'});
      const url=URL.createObjectURL(blob);
      const link=document.createElement('a');link.href=url;link.download='android-platform-simulation.json';link.click();
      setTimeout(()=>URL.revokeObjectURL(url),1000);
    });
  }catch(err){
    document.getElementById('signals').textContent='Local inspection failed: '+String(err);
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
echo '1) Firefox (local diagnostic; Client Hints may be unsupported)'
echo '2) Chrome / Chromium (local diagnostic; Client Hints when available)'
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
