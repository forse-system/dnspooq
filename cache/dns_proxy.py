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
BUFFER_SIZE = 4096  # Increased for DNSSEC responses

def packet_sniffer():
    """Original packet sniffer function"""
    def handler(pkt):
        if pkt.haslayer(DNSQR) and pkt.haslayer(UDP):
            query_type = pkt[DNSQR].qtype
            type_names = {1: 'A', 28: 'AAAA', 43: 'DS', 46: 'RRSIG', 48: 'DNSKEY'}
            type_str = type_names.get(query_type, str(query_type))
            print(f"Source port: {pkt[UDP].sport}, TXID: {pkt[DNS].id}, Query: {pkt[DNSQR].qname} Type: {type_str}")
    
    print("Sniffing DNS packets...")
    sniff(filter="udp port 53", prn=handler, store=0)

def dns_proxy():
    """DNS proxy with DNSSEC support and intentional delay"""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((LISTEN_IP, LISTEN_PORT))
    print(f"DNS proxy listening on {LISTEN_IP}:{LISTEN_PORT}")
    print(f"Buffer size: {BUFFER_SIZE} bytes (DNSSEC enabled)")
    
    while True:
        try:
            # Receive query from client with larger buffer for DNSSEC
            data, addr = sock.recvfrom(BUFFER_SIZE)
            
            # Parse DNS query
            dns_request = DNS(data)
            if dns_request.qr == 0:  # It's a query
                query_name = dns_request.qd.qname.decode()
                query_type = dns_request.qd.qtype
                type_names = {1: 'A', 28: 'AAAA', 43: 'DS', 46: 'RRSIG', 48: 'DNSKEY'}
                type_str = type_names.get(query_type, str(query_type))
                
                print(f"Received {type_str} query for {query_name} from {addr}")
                
                # Check for EDNS0 support
                if dns_request.arcount > 0:
                    print(f"  EDNS0 detected (arcount={dns_request.arcount})")
                
                # Create upstream socket
                upstream_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                upstream_sock.settimeout(5.0)  # Increased timeout for DNSSEC
                
                # Forward to upstream DNS
                upstream_sock.sendto(data, (UPSTREAM_DNS, UPSTREAM_PORT))
                
                # Add intentional delay for demonstration (except for DNSSEC queries)
                if query_type not in [43, 46, 48]:  # Don't delay DS, RRSIG, DNSKEY
                    print(f"Delaying response for {DELAY} seconds...")
                    time.sleep(DELAY)
                
                # Receive response from upstream with larger buffer
                try:
                    response, _ = upstream_sock.recvfrom(BUFFER_SIZE)
                    # Forward response back to client
                    sock.sendto(response, addr)
                    
                    # Parse response for logging
                    dns_response = DNS(response)
                    print(f"Forwarded {type_str} response for {query_name} (size: {len(response)} bytes)")
                    if dns_response.rcode == 2:  # SERVFAIL
                        print(f"  WARNING: SERVFAIL response")
                        
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