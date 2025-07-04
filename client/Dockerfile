FROM dorowu/ubuntu-desktop-lxde-vnc:focal

# Fix GPG error and install required packages
RUN rm -f /etc/apt/sources.list.d/google-chrome.list* && \
    apt-get update && apt-get install -y \
    firefox-locale-ja \
    fonts-noto-cjk \
    dnsutils \
    curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set Firefox to Japanese
RUN echo 'user_pref("intl.accept_languages", "ja, en-US, en");' >> /etc/firefox/syspref.js || true

# Set resolution
ENV RESOLUTION=1280x720