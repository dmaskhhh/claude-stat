#!/bin/bash
# Fetch real-time usage from claude.ai via Chrome AppleScript
# Requires: Chrome > View > Developer > Allow JavaScript from Apple Events

HUD_CACHE="$HOME/.claude/hud-cache.json"

# Use AppleScript to execute fetch in Chrome's claude.ai tab
RAW=$(osascript 2>/dev/null << 'APPLESCRIPT'
tell application "Google Chrome"
    if not running then return "NOT_RUNNING"
    repeat with w in windows
        set tabList to tabs of w
        repeat with i from 1 to count of tabList
            set t to item i of tabList
            if URL of t contains "claude.ai" then
                set jsCode to "
                    (async () => {
                        try {
                            let orgId = document.cookie.match(/lastActiveOrg=([^;]+)/)?.[1];
                            if (!orgId) {
                                const r = await fetch('/api/organizations');
                                const orgs = await r.json();
                                orgId = orgs[0]?.uuid;
                            }
                            if (!orgId) { document.title = 'USAGE_ERR:no_org'; return; }
                            const resp = await fetch('/api/organizations/' + orgId + '/usage');
                            const data = await resp.text();
                            document.title = 'USAGE:' + data;
                        } catch(e) {
                            document.title = 'USAGE_ERR:' + e.message;
                        }
                    })()
                "
                execute t javascript jsCode
                delay 1
                set pageTitle to title of t
                -- Restore original title
                execute t javascript "document.title = 'Claude'; void(0);"
                return pageTitle
            end if
        end repeat
    end repeat
    return "NO_TAB"
end tell
APPLESCRIPT
)

# Check result
case "$RAW" in
    USAGE:*)
        JSON="${RAW#USAGE:}"
        ;;
    NO_TAB|NOT_RUNNING|USAGE_ERR:*)
        exit 0  # Silently skip — browser not ready
        ;;
    *)
        exit 0
        ;;
esac

# Convert to hud-cache.json format
python3 -c "
import json, sys, time
from datetime import datetime, timezone

data = json.loads(sys.argv[1])
fh = data.get('five_hour', {})
sd = data.get('seven_day', {})

def iso_to_unix(s):
    if not s: return None
    s = s.replace('+00:00', 'Z').replace('+0000', 'Z')
    if '.' in s: s = s[:s.index('.')] + 'Z'
    return int(datetime.strptime(s, '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc).timestamp())

hud = {
    'rate_limits': {
        'five_hour': {
            'used_percentage': fh.get('utilization', 0) or 0,
            'resets_at': iso_to_unix(fh.get('resets_at')),
        },
        'seven_day': {
            'used_percentage': sd.get('utilization', 0) or 0,
            'resets_at': iso_to_unix(sd.get('resets_at')),
        },
    },
    'source': 'claude_ai_api',
    'fetched_at': int(time.time()),
}
print(json.dumps(hud))
" "$JSON" > "${HUD_CACHE}.tmp" 2>/dev/null && mv "${HUD_CACHE}.tmp" "$HUD_CACHE"
