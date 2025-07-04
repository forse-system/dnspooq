FROM python:3.8-alpine3.12
RUN apk add bash tcpdump bind-tools libpcap libpcap-dev && pip install scapy==2.4.4

WORKDIR /app
CMD ["python", "/app/dns_proxy.py"]
