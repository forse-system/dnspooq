#!/bin/bash
#
# VPCオーバーレイネットワーク上でDNSpooqが動作しない問題のデバッグスクリプト
# 各VMのホスト上で直接実行する（--network hostモード用）
#

set -e

# 色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# IPアドレス設定（環境に合わせて変更）
FORWARDER_IP="10.10.0.2"
ATTACKER_IP="10.10.0.3"
CACHE_IP="10.10.0.4"
MALICIOUS_IP="10.10.0.5"

# 現在のホスト情報
HOSTNAME=$(hostname)
MY_IP=$(hostname -I | awk '{print $1}')

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}VPC DNSpooq Debug Script${NC}"
echo -e "${BLUE}Host: $HOSTNAME ($MY_IP)${NC}"
echo -e "${BLUE}======================================${NC}\n"

# 1. 基本的なネットワーク情報
echo -e "${YELLOW}[1] ネットワーク基本情報${NC}"
echo "● インターフェース情報:"
ip -4 addr show | grep -E "^[0-9]+:|inet "
echo

echo "● ルーティングテーブル:"
ip route
echo

echo "● ARPテーブル (ip neigh):"
ip neigh show
echo

# 2. 接続性テスト
echo -e "${YELLOW}[2] VM間接続性テスト${NC}"
for name in "Forwarder:$FORWARDER_IP" "Attacker:$ATTACKER_IP" "Cache:$CACHE_IP"; do
    IFS=':' read -r label ip <<< "$name"
    if [ "$ip" != "$MY_IP" ]; then
        echo -n "● $label ($ip): "
        if ping -c 1 -W 1 $ip &>/dev/null; then
            echo -e "${GREEN}✓ 到達可能${NC}"
            # MACアドレス確認
            MAC=$(ip neigh show | grep "^$ip " | awk '{print $5}')
            [ ! -z "$MAC" ] && echo "  MAC: $MAC"
        else
            echo -e "${RED}✗ 到達不可${NC}"
        fi
    fi
done
echo

# 3. L2/L3スプーフィングテスト
echo -e "${YELLOW}[3] スプーフィングテスト${NC}"

# まずtcpdumpで監視を開始
SPOOF_PCAP="/tmp/spoof_test_$$.pcap"
echo "● スプーフィングテスト準備中..."

# Forwarder VMの場合は受信側のテスト
if [ "$HOSTNAME" = "vm-forwarder" ] || [ "$MY_IP" = "$FORWARDER_IP" ]; then
    echo "  Forwarder VMで実行中 - 偽装パケットの受信を監視"
    echo "  Cache IP ($CACHE_IP) からのパケットを5秒間監視..."
    
    # 監視開始
    sudo timeout 5 tcpdump -i any -nn "src host $CACHE_IP and dst host $MY_IP" -c 10 2>&1 | tee /tmp/spoof_receive.log &
    TCPDUMP_PID=$!
    
    echo "  Attacker VMでスプーフィングテストを実行してください"
    wait $TCPDUMP_PID 2>/dev/null || true
    
    # 結果判定
    if grep -q "$CACHE_IP" /tmp/spoof_receive.log 2>/dev/null; then
        echo -e "  ${GREEN}✓ 偽装パケットを受信 - スプーフィングが機能しています${NC}"
    else
        echo -e "  ${RED}✗ 偽装パケットが届いていません${NC}"
    fi
    rm -f /tmp/spoof_receive.log
    
# Attacker VMの場合は送信側のテスト
else
    echo "  偽装パケット送信テスト"
    
    # npingを使用（nmapパッケージに含まれる）
    if command -v nping &>/dev/null; then
        echo "  npingを使用してスプーフィングテスト"
        echo "  送信元: $CACHE_IP → 宛先: $FORWARDER_IP"
        sudo nping --udp -c 3 -S $CACHE_IP --source-port 12345 --dest-port 12345 $FORWARDER_IP 2>&1 | grep -E "(Sent|Rcvd|SENT|RCVD)" || echo "  nping実行完了"
    else
        echo -e "  ${RED}npingがインストールされていません${NC}"
        echo "  インストール: sudo apt-get install nmap"
    fi
    
    echo ""
    echo "  ※ Forwarder VMでtcpdumpを実行してパケットが届いたか確認してください"
    echo "  sudo tcpdump -i any -nn 'src host $CACHE_IP'"
fi
echo

# 4. tcpdumpによるパケット分析
echo -e "${YELLOW}[4] パケットキャプチャテスト${NC}"
echo "● 5秒間のDNSトラフィック監視:"

# バックグラウンドでキャプチャ
PCAP_FILE="/tmp/dns_capture_$$.pcap"
sudo timeout 5 tcpdump -i any -nn port 53 -w $PCAP_FILE 2>/dev/null &
TCPDUMP_PID=$!

# テストDNSクエリ送信
sleep 1
if [ "$HOSTNAME" = "vm-forwarder" ] || [ "$MY_IP" = "$FORWARDER_IP" ]; then
    echo "  Forwarder VMなのでスキップ"
else
    echo "  テストクエリ送信中..."
    dig @$FORWARDER_IP test.example.com +short +timeout=1 &>/dev/null || true
fi

# キャプチャ終了待ち
wait $TCPDUMP_PID 2>/dev/null || true

# 結果分析
if [ -f $PCAP_FILE ]; then
    PACKET_COUNT=$(sudo tcpdump -r $PCAP_FILE -nn 2>/dev/null | wc -l)
    echo "  キャプチャしたDNSパケット数: $PACKET_COUNT"
    
    if [ $PACKET_COUNT -gt 0 ]; then
        echo "  最初の5パケット:"
        sudo tcpdump -r $PCAP_FILE -nn 2>/dev/null | head -5 | sed 's/^/    /'
    fi
    rm -f $PCAP_FILE
fi
echo

# 5. セキュリティ設定確認
echo -e "${YELLOW}[5] セキュリティ設定確認${NC}"

echo "● Reverse Path Filtering (送信元検証):"
for conf in /proc/sys/net/ipv4/conf/*/rp_filter; do
    iface=$(echo $conf | cut -d'/' -f6)
    value=$(cat $conf)
    if [ $value -ne 0 ]; then
        echo -e "  $iface: ${RED}$value (有効)${NC}"
    else
        echo -e "  $iface: ${GREEN}$value (無効)${NC}"
    fi
done
echo

echo "● IP Forwarding:"
FWD=$(cat /proc/sys/net/ipv4/ip_forward)
if [ $FWD -eq 1 ]; then
    echo -e "  ${GREEN}有効${NC}"
else
    echo -e "  ${RED}無効${NC}"
fi
echo

echo "● iptables (DNS関連):"
sudo iptables -L -n -v | grep -E "(dpt:53|spt:53)" | head -5 || echo "  DNS関連ルールなし"
echo

# 6. DNSpooq攻撃シミュレーション
if [ "$HOSTNAME" = "vm-attacker" ] || [ "$MY_IP" = "$ATTACKER_IP" ]; then
    echo -e "${YELLOW}[6] DNSpooq攻撃シミュレーション${NC}"
    
    # シンプルなPythonスクリプトを生成
    cat > /tmp/test_spoof.py << 'EOF'
#!/usr/bin/env python3
import sys
import subprocess

def test_spoofing(forwarder_ip, cache_ip):
    print("● 偽装DNSレスポンス送信テスト")
    
    # scapyがあるか確認
    try:
        from scapy.all import *
        
        # テストパケット作成
        pkt = IP(src=cache_ip, dst=forwarder_ip)/UDP(sport=53, dport=33333)/\
              DNS(qr=1, aa=1, qd=DNSQR(qname="evil.test"), 
                  an=DNSRR(rrname="evil.test", ttl=300, rdata="6.6.6.6"))
        
        # 送信
        send(pkt, verbose=0)
        print(f"  ✓ 送信完了: {cache_ip} -> {forwarder_ip}")
        print("  tcpdumpでForwarder側の受信を確認してください")
        
    except ImportError:
        print("  ✗ scapyがインストールされていません")
        print("  別の方法でテスト...")
        
        # hping3でテスト
        cmd = f"sudo hping3 -2 -c 1 -a {cache_ip} -s 53 -p 33333 {forwarder_ip}"
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        if result.returncode == 0:
            print("  ✓ hping3での送信完了")
        else:
            print("  ✗ 送信失敗")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python test_spoof.py <forwarder_ip> <cache_ip>")
        sys.exit(1)
    test_spoofing(sys.argv[1], sys.argv[2])
EOF

    python3 /tmp/test_spoof.py $FORWARDER_IP $CACHE_IP
    rm -f /tmp/test_spoof.py
else
    echo -e "${YELLOW}[6] このVMはAttackerではないためスキップ${NC}"
fi
echo

# 7. 診断結果まとめ
echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}診断結果サマリー${NC}"
echo -e "${BLUE}======================================${NC}"

# 問題の可能性を判定
ISSUES=()

# RPフィルタチェック
if [ $(cat /proc/sys/net/ipv4/conf/all/rp_filter) -ne 0 ]; then
    ISSUES+=("Reverse Path Filteringが有効 - IPスプーフィングがブロックされる")
fi

# ARPチェック
ARP_COUNT=$(ip neigh show | grep -c "10.10.0" || true)
if [ $ARP_COUNT -lt 2 ]; then
    ISSUES+=("ARPエントリが少ない - VM間の通信に問題がある可能性")
fi

if [ ${#ISSUES[@]} -gt 0 ]; then
    echo -e "${RED}検出された問題:${NC}"
    for issue in "${ISSUES[@]}"; do
        echo "  - $issue"
    done
else
    echo -e "${GREEN}明らかな問題は検出されませんでした${NC}"
fi

echo
echo -e "${YELLOW}推奨事項:${NC}"
echo "1. Forwarder VMでtcpdumpを実行して偽装パケットが届くか確認"
echo "   sudo tcpdump -i any -nn 'src host $CACHE_IP and dst port 53'"
echo
echo "2. RPフィルタを無効化してテスト"
echo "   sudo sysctl -w net.ipv4.conf.all.rp_filter=0"
echo
echo "3. VPCのセキュリティ設定を確認（AWS/GCP/Azure CLIで）"
echo "   - ソース/デスティネーションチェック"
echo "   - セキュリティグループのルール"
echo

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}デバッグ完了${NC}"
echo -e "${BLUE}======================================${NC}"