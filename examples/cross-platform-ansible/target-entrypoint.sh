#!/usr/bin/env sh
set -eu

if [ -f /keys/id_ed25519.pub ]; then
  cat /keys/id_ed25519.pub > /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys
fi

exec /usr/sbin/sshd -D -e
