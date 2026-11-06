#!/system/bin/sh
# 卸载模块时清理：移除 netfilter 规则并强杀进程
# （规则随重启也会全部消失）
for pkg in com.mobiletools.systemhelper com.miui.guardprovider com.miui.securityinputmethod; do
    uid=$(pm list packages -U 2>/dev/null | grep -w "$pkg" | sed 's/.*uid://')
    [ -z "$uid" ] && continue
    for bin in iptables ip6tables; do
        command -v "$bin" >/dev/null 2>&1 || continue
        "$bin" -D OUTPUT -m owner --uid-owner "$uid" -j DROP 2>/dev/null
        "$bin" -D INPUT  -m owner --uid-owner "$uid" -j DROP 2>/dev/null
    done
done
