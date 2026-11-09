FROM docker.io/nginxinc/nginx-unprivileged:1.27-alpine@sha256:025de0b541bcc6cfbf508e4201aaa37b51d34daaf6d52e5e2753e29a8ddaa869

COPY services/frontend/nginx.conf /etc/nginx/conf.d/default.conf
COPY services/frontend/index.html /usr/share/nginx/html/index.html
COPY services/frontend/styles.css /usr/share/nginx/html/styles.css
COPY services/frontend/app.js /usr/share/nginx/html/app.js

