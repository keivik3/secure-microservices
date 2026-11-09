FROM docker.io/nginxinc/nginx-unprivileged:1.27-alpine@sha256:65e3e85dbaed8ba248841d9d58a899b6197106c23cb0ff1a132b7bfe0547e4c0

COPY services/frontend/nginx.conf /etc/nginx/conf.d/default.conf
COPY services/frontend/index.html /usr/share/nginx/html/index.html
COPY services/frontend/styles.css /usr/share/nginx/html/styles.css
COPY services/frontend/app.js /usr/share/nginx/html/app.js

