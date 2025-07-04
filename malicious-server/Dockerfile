FROM nginx:alpine

# Nginxの設定とコンテンツをコピー
COPY nginx.conf /etc/nginx/nginx.conf
COPY fake-site/* /usr/share/nginx/html/

# ポート80を公開
EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]