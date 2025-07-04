#!/usr/bin/python

import socket
import time
import threading
from scapy.all import *

# Configuration
LISTEN_IP = "0.0.0.0"
LISTEN_PORT = 53
UPSTREAM_DNS = "8.8.8.8"
UPSTREAM_PORT = 53
DELAY = 2.0  # 2 seconds delay to give attacker more chance

def packet_sniffer():
    """Original packet sniffer function"""
    def handler(pkt):
        if pkt.haslayer(DNSQR) and pkt.haslayer(UDP):
            print(f"Source port: {pkt[UDP].sport}, TXID: {pkt[DNS].id}, Query: {pkt[DNSQR].qname}")
    
    print("Sniffing DNS packets...")
    sniff(filter="udp port 53", prn=handler, store=0)

def dns_proxy():
    """DNS proxy with intentional delay"""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((LISTEN_IP, LISTEN_PORT))
    print(f"DNS proxy listening on {LISTEN_IP}:{LISTEN_PORT}")
    
    while True:
        try:
            # Receive query from client
            data, addr = sock.recvfrom(512)
            
            # Parse DNS query
            dns_request = DNS(data)
            if dns_request.qr == 0:  # It's a query
                query_name = dns_request.qd.qname.decode()
                print(f"Received query for {query_name} from {addr}")
                
                # Create upstream socket
                upstream_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                upstream_sock.settimeout(2.0)
                
                # Forward to upstream DNS
                upstream_sock.sendto(data, (UPSTREAM_DNS, UPSTREAM_PORT))
                
                # Add intentional delay for demonstration
                print(f"Delaying response for {DELAY} seconds...")
                time.sleep(DELAY)
                
                # Receive response from upstream
                try:
                    response, _ = upstream_sock.recvfrom(512)
                    # Forward response back to client
                    sock.sendto(response, addr)
                    print(f"Forwarded response for {query_name}")
                except socket.timeout:
                    print(f"Upstream timeout for {query_name}")
                
                upstream_sock.close()
                
        except Exception as e:
            print(f"Error: {e}")

if __name__ == "__main__":
    # Start packet sniffer in a separate thread
    sniffer_thread = threading.Thread(target=packet_sniffer)
    sniffer_thread.daemon = True
    sniffer_thread.start()
    
    # Start DNS proxy
    dns_proxy()