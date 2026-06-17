#!/bin/bash
mkdir /root/.config
cp -r /tmp/opencode-config /root/.config/opencode
sed -i 's/localhost/host.container.internal/g' /root/.config/opencode/opencode.jsonc
mkdir -p /root/.local/share
cp -r /tmp/opencode-data /root/.local/share/opencode
exec "$@"
