#!/usr/bin/env bash
# ==============================================================================
# SysTFTP - macOS Privileged Port Forwarding Helper
# Redirects standard ports 69 (TFTP), 21 (FTP), 514 (Syslog) to
# unprivileged user ports 6969, 2121, 5140 via macOS pf (Packet Filter).
# This allows SysTFTP to run smoothly as a normal user without root!
# ==============================================================================

echo "Setting up macOS packet filter port redirection for SysTFTP..."

PF_CONF="/tmp/systftp_pf.conf"
cat << 'EOF' > "${PF_CONF}"
# TFTP (UDP 69 -> 6969)
rdr pass on any inet proto udp from any to any port 69 -> 127.0.0.1 port 6969
# FTP (TCP 21 -> 2121)
rdr pass on any inet proto tcp from any to any port 21 -> 127.0.0.1 port 2121
# Syslog (UDP 514 -> 5140)
rdr pass on any inet proto udp from any to any port 514 -> 127.0.0.1 port 5140
EOF

echo "Applying pf rules with sudo..."
sudo pfctl -ef "${PF_CONF}"

echo "Port redirection active! You can now run SysTFTP with ports 6969, 2121, 5140"
echo "and network switches/routers can connect to standard ports 69, 21, 514 directly."
