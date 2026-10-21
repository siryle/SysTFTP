#!/bin/sh
set -eu
export LC_ALL=C

ACTION="${1:-status}"
ANCHOR="com.apple/SysTFTP"
STATE_DIR="/var/run/systftp-pf"
TOKEN_FILE="${STATE_DIR}/token"

case "$ACTION" in enable|disable|status) ;; *) echo "Unknown action" >&2; exit 2 ;; esac
if [ "$(/usr/bin/id -u)" -ne 0 ]; then
    echo "需要管理员授权才能管理标准端口转发。" >&2
    exit 1
fi

enabled() {
    info="$(/sbin/pfctl -s info 2>/dev/null)" || return 2
    printf '%s\n' "$info" | /usr/bin/grep -q '^Status: Enabled' || return 1
    rules="$(/sbin/pfctl -a "$ANCHOR" -s nat 2>/dev/null)" || return 2
    # PF expands "self" into multiple addresses; validate mappings, not rule count.
    printf '%s\n' "$rules" | /usr/bin/awk '
        /^rdr pass on ! lo0 inet proto udp / && / port (= )?69 -> 127[.]0[.]0[.]1 port 6969([[:space:]]|$)/ { tftp = 1 }
        /^rdr pass on ! lo0 inet proto tcp / && / port (= )?21 -> 127[.]0[.]0[.]1 port 2121([[:space:]]|$)/ { ftp = 1 }
        /^rdr pass on ! lo0 inet proto udp / && / port (= )?514 -> 127[.]0[.]0[.]1 port 5140([[:space:]]|$)/ { syslog = 1 }
        END { exit !(tftp && ftp && syslog) }
    '
}

if [ "$ACTION" = status ]; then
    if enabled; then
        echo SYSTFTP_PF_ENABLED
    else
        result=$?
        if [ "$result" -ne 1 ]; then
            echo "无法读取系统 PF 状态，请检查系统防火墙后重试。" >&2
            exit 1
        fi
        echo SYSTFTP_PF_DISABLED
    fi
    exit 0
fi

# Only our runtime directory, anchor and enable reference belong to SysTFTP.
# Never reload /etc/pf.conf or disable PF globally.
if [ -L "$STATE_DIR" ]; then echo "转发状态目录不能是符号链接。" >&2; exit 1; fi
/usr/bin/install -d -o root -g wheel -m 700 "$STATE_DIR"
if ! /bin/mkdir "${STATE_DIR}/lock" 2>/dev/null; then
    echo "另一个端口转发操作正在运行，请稍后重试。" >&2
    exit 1
fi
RULES=""
BACKUP=""
NEW_TOKEN=""
COMMITTED=false
ROLLBACK_READY=false
cleanup() {
    if [ "$COMMITTED" = false ] && [ "$ROLLBACK_READY" = true ]; then
        /sbin/pfctl -a "$ANCHOR" -f "$BACKUP" >/dev/null 2>&1 ||
            echo "无法恢复此前的 SysTFTP 转发规则，请检查转发状态。" >&2
    fi
    if [ "$COMMITTED" = false ] && [ -n "$NEW_TOKEN" ]; then
        /sbin/pfctl -X "$NEW_TOKEN" >/dev/null 2>&1 || true
    fi
    [ -z "$RULES" ] || /bin/rm -f "$RULES"
    [ -z "$BACKUP" ] || /bin/rm -f "$BACKUP"
    /bin/rmdir "${STATE_DIR}/lock"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

if [ "$ACTION" = disable ]; then
    /sbin/pfctl -a "$ANCHOR" -F nat >/dev/null
    if [ -f "$TOKEN_FILE" ]; then
        token="$(/bin/cat "$TOKEN_FILE")"
        case "$token" in ''|*[!0-9]*) echo "无效的转发状态，请联系管理员。" >&2; exit 1 ;; esac
        /sbin/pfctl -X "$token" >/dev/null 2>&1 || true
        /bin/rm -f "$TOKEN_FILE"
    fi
    COMMITTED=true
    echo SYSTFTP_PF_DISABLED
    exit 0
fi

# macOS provides this wildcard entry for dynamically managed anchors.
# Refuse to replace a customized main ruleset that does not contain it.
if ! /sbin/pfctl -s nat | /usr/bin/grep -Fq 'rdr-anchor "com.apple/*"'; then
    echo "系统 PF 主规则缺少 com.apple/* 转发入口。请管理员检查自定义防火墙配置，或直接使用普通端口。" >&2
    exit 1
fi

RULES="$(/usr/bin/mktemp "${STATE_DIR}/rules.XXXXXX")"
cat > "$RULES" <<'RULES'
rdr pass on ! lo0 inet proto udp from any to self port 69 -> 127.0.0.1 port 6969
rdr pass on ! lo0 inet proto tcp from any to self port 21 -> 127.0.0.1 port 2121
rdr pass on ! lo0 inet proto udp from any to self port 514 -> 127.0.0.1 port 5140
RULES
/sbin/pfctl -a "$ANCHOR" -nf "$RULES"
BACKUP="$(/usr/bin/mktemp "${STATE_DIR}/backup.XXXXXX")"
/sbin/pfctl -a "$ANCHOR" -s nat > "$BACKUP"
ROLLBACK_READY=true

token=""
if [ -f "$TOKEN_FILE" ]; then token="$(/bin/cat "$TOKEN_FILE")"; fi
case "$token" in *[!0-9]*) token="" ;; esac
if [ -z "$token" ] || ! /sbin/pfctl -s References 2>/dev/null | /usr/bin/grep -Eq "(^|[[:space:]])${token}([[:space:]]|$)"; then
    enable_output="$(/sbin/pfctl -E 2>&1)"
    NEW_TOKEN="$(printf '%s\n' "$enable_output" | /usr/bin/awk '/Token[[:space:]]*:/ {print $NF}')"
    case "$NEW_TOKEN" in
        ''|*[!0-9]*) echo "无法取得 PF 启用引用，未应用转发规则。" >&2; exit 1 ;;
    esac
    token="$NEW_TOKEN"
fi

/sbin/pfctl -a "$ANCHOR" -f "$RULES"
if ! enabled; then echo "未能验证转发规则，已回滚此次操作。" >&2; exit 1; fi
printf '%s\n' "$token" > "$TOKEN_FILE"
/bin/chmod 600 "$TOKEN_FILE"
COMMITTED=true
echo SYSTFTP_PF_ENABLED
