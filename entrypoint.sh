#!/bin/bash

# Copy OpenCode config
mkdir /root/.config
cp -r /tmp/opencode-config /root/.config/opencode

# Copy OpenCode data
mkdir -p /root/.local/share
cp -r /tmp/opencode-data /root/.local/share/opencode

# Copy OpenCode state
mkdir -p /root/.local/state
cp -r /tmp/opencode-state /root/.local/state/opencode

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
