#!/system/bin/sh
# FuckMIUIHelperService!
# post-fs-data: 在 PackageManager 扫描之前把目标应用目录 bind-mount 成空目录
MODDIR=${0%/*}
EMPTY="$MODDIR/empty"
LOG=/data/local/tmp/FuckMIUIHelperService.log
mkdir -p "$EMPTY"

log() {
    echo "$(date '+%m-%d %H:%M:%S') $*" >> "$LOG"
    # 日志超过 64KB 自动截断，只保留最近 100 行
    if [ "$(stat -c %s "$LOG" 2>/dev/null || echo 0)" -gt 65536 ]; then
        tail -n 100 "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG"
    fi
}
log "==== post-fs-data start ===="

HIDE_DIRS="/system/priv-app/SystemHelper
/system/app/SystemHelper
/system_ext/priv-app/SystemHelper
/product/app/MIUIGuardProvider
/product/app/MIUISecurityInputMethod
/product/priv-app/MIUIGuardProvider
/vendor/app/MIUIGuardProvider
/odm/app/MIUIGuardProvider
/vendor/priv-app/SystemHelper
/odm/priv-app/SystemHelper
/product/pangu/system/priv-app/SystemHelper"

for base in /system/priv-app /system/app /system_ext/priv-app /system_ext/app \
            /product/app /product/priv-app /vendor/app /vendor/priv-app \
            /odm/app /odm/priv-app /product/pangu/system/priv-app; do
    [ -d "$base" ] || continue
    for d in "$base"/*; do
        [ -d "$d" ] || continue
        case "$d" in
            *SystemHelper*|*MIUIGuardProvider*|*GuardProvider*|*SecurityInputMethod*) HIDE_DIRS="$HIDE_DIRS
$d" ;;
        esac
    done
done

for d in $HIDE_DIRS; do
    [ -d "$d" ] || continue
    if mountpoint -q "$d" 2>/dev/null; then
        log "already hidden: $d"
    else
        if mount --bind "$EMPTY" "$d" 2>/dev/null; then
            log "hidden: $d"
        else
            log "FAILED hide: $d"
        fi
    fi
done

log "==== post-fs-data done ===="
