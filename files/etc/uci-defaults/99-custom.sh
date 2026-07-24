#!/bin/sh
# 99-custom.sh — 固件首次启动时运行
# 设置默认 IP、nginx、quickfile 配置等

LOGFILE="/etc/config/img-build-log.txt"
echo "Starting 99-custom.sh at $(date)" >> $LOGFILE

# ============= 默认 IP 192.168.50.5 =============
uci set network.lan.ipaddr='192.168.50.5'
uci set network.lan.netmask='255.255.255.0'
uci set network.lan.gateway='192.168.50.1'
uci set network.lan.dns='223.5.5.5 114.114.114.114'
uci commit network
echo "✅ 默认 IP 已设为 192.168.50.5" >> $LOGFILE

# ============= luci-app-quickfile nginx 配置 =============
# 替换为指定配置
if [ -f /usr/bin/quickfile ]; then
  echo "🔄 配置 quickfile nginx..." >> $LOGFILE
  uci set nginx.global.uci_enable='true'
  uci del nginx._lan 2>/dev/null
  uci del nginx._redirect2ssl 2>/dev/null
  uci add nginx server
  uci rename nginx.@server[-1]='_lan'
  uci set nginx._lan.server_name='_lan'
  uci add_list nginx._lan.listen='80 default_server'
  uci add_list nginx._lan.listen='[::]:80 default_server'
  uci add_list nginx._lan.include='conf.d/*.locations'
  uci set nginx._lan.access_log='off; # logd openwrt'
  uci commit nginx
  echo "✅ nginx quickfile 配置完成" >> $LOGFILE
fi

# ============= 无密码 root 登录 =============
# dropbear 默认允许空密码，无需额外设置

# ============= 防火墙 =============
uci set firewall.@zone[1].input='ACCEPT'
uci commit firewall

# ============= 主机名映射（解决安卓 TV DNS 问题） =============
uci add dhcp domain
uci set "dhcp.@domain[-1].name=time.android.com"
uci set "dhcp.@domain[-1].ip=203.107.6.88"
uci commit dhcp

exit 0
