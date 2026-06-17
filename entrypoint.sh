#!/bin/bash

# Copy OpenCode config
mkdir /root/.config
cp -r /tmp/opencode-config /root/.config/opencode

# Copy other OpenCode things
mkdir -p /root/.local/share/opencode
[[ -f /tmp/opencode-data/mcp-auth.json ]] && cp /tmp/opencode-data/mcp-auth.json /root/.local/share/opencode/

# Replace LLM endpoints to host.container.internal
sed -i 's/localhost/host.container.internal/g' /root/.config/opencode/opencode.json
# Replace permissions object with {} (ie. yolo mode)
python3 -c "
import re, json
path='/root/.config/opencode/opencode.json'
raw = open(path).read()
cfg = json.loads(re.sub(r',\s*([}\]])', r'\1', raw))
cfg['permission'] = {}
open(path, 'w').write(json.dumps(cfg, indent=2) + '\n')
"

exec "$@"
