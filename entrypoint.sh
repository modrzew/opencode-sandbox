#!/bin/bash
mkdir /root/.config
cp -r /tmp/opencode-config /root/.config/opencode
sed -i 's/localhost/host.container.internal/g' /root/.config/opencode/opencode.jsonc
exec "$@"
