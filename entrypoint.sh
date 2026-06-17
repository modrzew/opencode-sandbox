#!/bin/bash

# Copy OpenCode config
mkdir /root/.config
cp -r /tmp/opencode-config /root/.config/opencode

# Copy other OpenCode things
mkdir -p /root/.local/share
[[ -f /tmp/opencode-data/mcp-auth.json ]] && cp /tmp/opencode-data/mcp-auth.json /root/.local/share/opencode/

# Replace LLM endpoints to host.container.internal
sed -i 's/localhost/host.container.internal/g' /root/.config/opencode/opencode.jsonc
# Replace permissions object with {} (ie. yolo mode)
python3 -c "
import re, json
with open('/root/.config/opencode/opencode.jsonc') as f:
    raw = f.read()
# Strip comments to get valid JSON
cleaned = re.sub(r'//[^\\n]*', '', raw)
cleaned = re.sub(r'/\*.*?\*/', '', cleaned, flags=re.DOTALL)
cfg = json.loads(cleaned)
cfg['permission'] = {}
# Preserve original formatting: just swap the permission block
json_str = json.dumps(cfg, indent=2)
with open('/root/.config/opencode/opencode.jsonc', 'w') as f:
    f.write(json_str + '\\n')
"

exec "$@"
