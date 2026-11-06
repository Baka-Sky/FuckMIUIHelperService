#!/system/bin/sh
# FuckMIUIHelperService!
# service: 低开销看门狗 + 按 UID 在 netfilter 层封死所有协议出站流量
MODDIR=${0%/*}
EMPTY="$MODDIR/empty"
LOG=/data/local/tmp/FuckMIUIHelperService.log
PKGS="com.mobiletools.systemhelper com.miui.guardprovider com.miui.securityinputmethod com.xiaomi.trustservice"
RULES=/data/local/tmp/FuckMIUIHelperService.uids
mkdir -p "$EMPTY"

# 所有可能卡住的系统命令都套超时，单条最长 5 秒；timeout 不可用则裸跑
TO=""
command -v timeout >/dev/null 2>&1 && TO="timeout 5"

# 降低自身调度优先级，几乎不占 CPU
renice 19 $$ 2>/dev/null

LOG_MAX=65536
log() {
    echo "$(date '+%m-%d %H:%M:%S') $*" >> "$LOG"
    # 日志超过 64KB 自动截断，只保留最近 100 行
    if [ "$(stat -c %s "$LOG" 2>/dev/null || echo 0)" -gt "$LOG_MAX" ]; then
        tail -n 100 "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG"
    fi
}

block_uid() {
    pkg="$1"
    uid="$2"
    [ -z "$uid" ] && return
    # 记录 pkg/uid/时间，供包消失后自动回收规则
    grep -v "^$pkg " "$RULES" 2>/dev/null > "$RULES.tmp"
    echo "$pkg $uid $(date +%s)" >> "$RULES.tmp"
    mv -f "$RULES.tmp" "$RULES"
    added=0
    for bin in iptables ip6tables; do
        command -v "$bin" >/dev/null 2>&1 || continue
        for chain in OUTPUT INPUT; do
            if ! $TO "$bin" -C "$chain" -m owner --uid-owner "$uid" -j DROP 2>/dev/null; then
                $TO "$bin" -I "$chain" 1 -m owner --uid-owner "$uid" -j DROP 2>/dev/null && added=1
            fi
        done
    done
    # 只在真正新插入规则时写日志，避免重复刷屏
    [ "$added" -eq 1 ] && log "netfilter DROP uid=$uid (TCP/UDP/QUIC/DNS/HTTP/HTTPS all)"
}

# 纯文件系统判断，不经过 PackageManager，开销接近 0
fast_present() {
    for d in /data/app/*/*; do
        case "${d##*/}" in
            *"$1"*) return 0 ;;
        esac
    done
    return 1
}

nuke_pkg() {
    pkg="$1"
    # 文件系统里没有这个包就直接跳过，不碰 PackageManager
    fast_present "$pkg" || return
    uid=$($TO dumpsys package "$pkg" 2>/dev/null | sed -n 's/.*userId=\([0-9]*\).*/\1/p' | head -n 1)
    [ -z "$uid" ] && uid=$($TO pm list packages -U 2>/dev/null | grep -w "$pkg" | sed 's/.*uid://')
    now=$(date +%s)
    LAST="/data/local/tmp/FuckMIUIHelperService.last.$pkg"
    last=$(cat "$LAST" 2>/dev/null || echo 0)
    if [ $((now - last)) -ge 60 ]; then
        log "detected $pkg uid=${uid:-unknown} -> nuke"
        echo "$now" > "$LAST"
    fi
    # 查不到 UID 就跳过封网这一步，继续后面的卸载动作，不阻塞主循环
    [ -n "$uid" ] && block_uid "$pkg" "$uid"
    $TO am force-stop "$pkg" 2>/dev/null
    $TO appops set "$pkg" RUN_IN_BACKGROUND deny 2>/dev/null
    $TO appops set "$pkg" RUN_ANY_IN_BACKGROUND deny 2>/dev/null
    $TO appops set "$pkg" START_FOREGROUND deny 2>/dev/null
    $TO pm suspend --user 0 "$pkg" 2>/dev/null
    $TO pm disable-user --user 0 "$pkg" 2>/dev/null
    $TO pm uninstall --user 0 "$pkg" 2>/dev/null
    $TO pm uninstall "$pkg" 2>/dev/null
    pkill -f "$pkg" 2>/dev/null
    rm -rf /data/app/*"$pkg"* /data/data/"$pkg" /data/user/0/"$pkg" \
           /data/user_de/0/"$pkg" /data/misc/profiles/cur/0/"$pkg" \
           /data/misc/profiles/ref/"$pkg" 2>/dev/null
}

cleanup_uids() {
    [ -f "$RULES" ] || return
    now=$(date +%s)
    keep=""
    while read pkg uid ts; do
        [ -z "$uid" ] && continue
        if fast_present "$pkg"; then
            keep="${keep}${pkg} ${uid} ${ts}
"
            continue
        fi
        if [ $((now - ts)) -ge 60 ]; then
            for bin in iptables ip6tables; do
                command -v "$bin" >/dev/null 2>&1 || continue
                $TO "$bin" -D OUTPUT -m owner --uid-owner "$uid" -j DROP 2>/dev/null
                $TO "$bin" -D INPUT -m owner --uid-owner "$uid" -j DROP 2>/dev/null
            done
            log "cleanup netfilter rules uid=$uid ($pkg gone > 60s)"
        else
            keep="${keep}${pkg} ${uid} ${ts}
"
        fi
    done < "$RULES"
    printf "%s" "$keep" > "$RULES"
}

rehide() {
    for base in /system/priv-app /system/app /system_ext/priv-app /product/app \
                /product/priv-app /product/pangu/system/priv-app /vendor/app /odm/app; do
        [ -d "$base" ] || continue
        for d in "$base"/*; do
            [ -d "$d" ] || continue
            case "$d" in
                *SystemHelper*|*MIUIGuardProvider*|*GuardProvider*|*SecurityInputMethod*|*MiTrust*)
                    mountpoint -q "$d" 2>/dev/null || mount --bind "$EMPTY" "$d" 2>/dev/null
                    ;;
            esac
        done
    done
}

while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done
log "==== service start ===="

# 首轮清理
for pkg in $PKGS; do nuke_pkg "$pkg"; done

# 启动时先裁一次历史日志，避免旧文件过大
if [ "$(stat -c %s "$LOG" 2>/dev/null || echo 0)" -gt "$LOG_MAX" ]; then
    tail -n 100 "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG"
fi

# 主循环：每轮只做两次目录通配 + 挂载点检查；命中才触发重活
while true; do
    for pkg in $PKGS; do nuke_pkg "$pkg"; done
    cleanup_uids
    rehide
    sleep 10
done
