#!/system/bin/sh
# 安装时只需要两件事：给 hosts 打对标签、设好可用位。
# 挂载由 KernelSU metamodule（Hybrid Mount）在开机时自动完成。

H="$MODPATH/system/etc/hosts"

if [ -f "$H" ]; then
  # 标签必须是 system_file，否则 netd / DNS 解析器读不到，hosts 会被静默忽略
  chcon u:object_r:system_file:s0 "$H" 2>/dev/null
fi

set_perm_recursive "$MODPATH" 0 0 0755 0644

ui_print "- ColorOS Telemetry Blocker: $(grep -c '^0.0.0.0' "$H" 2>/dev/null) 条域名"
ui_print "- 挂载: Hybrid Mount（开机自动）"
ui_print "- 编辑: 模块页 → 打开"
