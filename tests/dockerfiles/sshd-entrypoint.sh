#!/usr/bin/env bash
# Copyright the say-hi contributors.
# SPDX-License-Identifier: MIT
# The sshd container entrypoint's common tail, past a caller's own shebang
# and login-shell setup: seed hitest's authorized_keys from $PUBKEY, generate
# host keys, exec sshd locked down (password auth, root login and PAM all
# off - $SSHD_OPTS layers more on top). Sourced by tests/lib/ssh.sh's
# _hi_sshd_entrypoint (which prepends the shebang and, for the full-login
# image, a usermod line) and by docs/tapes/fixtures.sh, which has no test
# harness to source but already depends on this directory's
# sshd-debian.Dockerfile - so the two entrypoints cannot drift apart the way
# two independent heredocs did.
_HI_SSHD_ENTRYPOINT_BODY="$(
  cat <<'EOF'
echo "hitest:*" | chpasswd -e
chown hitest:hitest /home/hitest
install -d -m 700 -o hitest -g hitest /home/hitest/.ssh
printf '%s\n' "$PUBKEY" >/home/hitest/.ssh/authorized_keys
chown hitest:hitest /home/hitest/.ssh/authorized_keys
chmod 600 /home/hitest/.ssh/authorized_keys
ssh-keygen -A >/dev/null
exec /usr/sbin/sshd -D -e -o PasswordAuthentication=no -o PermitRootLogin=no -o UsePAM=no $SSHD_OPTS
EOF
)"
