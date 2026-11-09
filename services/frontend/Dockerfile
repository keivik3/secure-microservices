FROM docker.io/nginxinc/nginx-unprivileged:1.27-alpine

COPY services/frontend/nginx.conf /etc/nginx/conf.d/default.conf
COPY services/frontend/index.html /usr/share/nginx/html/index.html
COPY services/frontend/styles.css /usr/share/nginx/html/styles.css
COPY services/frontend/app.js /usr/share/nginx/html/app.js

