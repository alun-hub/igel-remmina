#!/bin/bash
# URI handler for rdp:// and remmina:// links
# Called by Chromium when user clicks an rdp:// or remmina:// link
#
# Supported URI formats:
#   rdp://host[:port][?username=USER&domain=DOMAIN]
#   remmina://rdp/host[:port]
#
# Remmina is launched with a temporary .remmina profile that enables
# smartcard passthrough.

URI="$1"

if [ -z "$URI" ]; then
    echo "Usage: $0 rdp://host[:port][?username=USER&domain=DOMAIN]"
    exit 1
fi

# Determine protocol and strip scheme
if [[ "$URI" == rdp://* ]]; then
    STRIPPED="${URI#rdp://}"
elif [[ "$URI" == remmina://* ]]; then
    STRIPPED="${URI#remmina://rdp/}"
else
    STRIPPED="$URI"
fi

# Split host:port and query string
HOSTPORT="${STRIPPED%%\?*}"
QUERY="${STRIPPED#*\?}"

HOST="${HOSTPORT%%:*}"
PORT="${HOSTPORT##*:}"
[ "$PORT" = "$HOST" ] && PORT="3389"

# Parse query params
RDP_USER=""
RDP_DOMAIN=""

if [ "$QUERY" != "$STRIPPED" ]; then
    IFS='&' read -ra PARAMS <<< "$QUERY"
    for param in "${PARAMS[@]}"; do
        key="${param%%=*}"
        val="${param#*=}"
        case "$key" in
            username|user) RDP_USER="$val" ;;
            domain)        RDP_DOMAIN="$val" ;;
            port)          PORT="$val" ;;
        esac
    done
fi

# Write a temporary Remmina profile with smartcard enabled
PROFILE=$(mktemp /tmp/remmina-XXXXXX.remmina)
trap "rm -f $PROFILE" EXIT

cat > "$PROFILE" <<EOF
[remmina]
name=${HOST}
protocol=RDP
server=${HOST}:${PORT}
username=${RDP_USER}
domain=${RDP_DOMAIN}
password=
smartcard_redirect=1
dynamic_resolution_enabled=1
clipboard_mode=1
sound=local
quality=2
EOF

exec /opt/remmina/bin/remmina "$PROFILE"
