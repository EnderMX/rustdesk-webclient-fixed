# syntax=docker/dockerfile:1.7

###############################################################################
# Stage 1 — Build JS/TS
###############################################################################
FROM node:18-slim AS js-build

ARG RUSTDESK_REPO=MonsieurBiche/rustdesk-web-client
ARG RUSTDESK_TAG=fix-build


RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        git python3 python-is-python3 protobuf-compiler \
        ca-certificates build-essential && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /src

RUN git clone --branch "${RUSTDESK_TAG}" \
        --depth 1 \
        --recursive --shallow-submodules \
        "https://github.com/${RUSTDESK_REPO}.git" rustdesk && \
    cd rustdesk && \
    git submodule update --init --recursive --depth 1

WORKDIR /src/rustdesk/flutter/web

RUN if [ -d "v1" ]; then cp -a v1/* .; fi

WORKDIR /src/rustdesk/flutter/web/js

# Install deps
RUN corepack enable && \
    corepack prepare "yarn@1.22.22" --activate && \
    yarn install --non-interactive --silent

# Fix 1 — pin libsodium to CJS-only version
RUN yarn add libsodium-wrappers@0.7.11 --exact --non-interactive 2>/dev/null || true

# Fix 2 — force CJS resolution for libsodium in vite
RUN node -e "\
const fs=require('fs'); \
const p='vite.config.js'; \
let c=fs.readFileSync(p,'utf8'); \
if(!c.includes('optimizeDeps')){ \
  c=c.replace('plugins:', \"optimizeDeps: { include: ['libsodium-wrappers'] },\nplugins:\"); \
  fs.writeFileSync(p,c); \
}"

# Fix 3 — resolve libsodium.mjs alias in vite
RUN node -e "\
const fs=require('fs'); \
const p='vite.config.js'; \
let c=fs.readFileSync(p,'utf8'); \
const alias=\`resolve: { alias: { './libsodium.mjs': require.resolve('libsodium-wrappers/dist/modules-esm/libsodium.js') } },\`; \
if(!c.includes('libsodium.mjs')){ \
  c=c.replace('optimizeDeps:', alias+'\noptimizeDeps:'); \
  fs.writeFileSync(p,c); \
}" 2>/dev/null || true

# Fix 4 — skipLibCheck in tsconfig
RUN node -e "\
const fs=require('fs'); \
const p='tsconfig.json'; \
const c=JSON.parse(fs.readFileSync(p,'utf8')); \
c.compilerOptions=c.compilerOptions||{}; \
c.compilerOptions.skipLibCheck=true; \
fs.writeFileSync(p,JSON.stringify(c,null,2));"



# Force WSS and point to correct server
RUN find /src/rustdesk/flutter/web/js/src -name "*.ts" | \
    xargs sed -i \
    -e 's|rs-sg\.rustdesk\.com|BACKEND_HOST_PLACEHOLDER|g' \
    -e 's|rs-ny\.rustdesk\.com|BACKEND_HOST_PLACEHOLDER|g' \
    -e 's|rs-cn\.rustdesk\.com|BACKEND_HOST_PLACEHOLDER|g' \
    2>/dev/null || true




# Fix 5 duplicate SE identifier
RUN sed -i 's/function SE(o,s,c)/function SE_msgbox(o,s,c)/g' \
    /src/rustdesk/flutter/web/js/src/connection.ts 2>/dev/null || true && \
    sed -i 's/SE(o,s,c)/SE_msgbox(o,s,c)/g' \
    /src/rustdesk/flutter/web/js/src/connection.ts 2>/dev/null || true




# Build JS
RUN yarn build

###############################################################################
# Stage 2 — Flutter Web Build
###############################################################################
FROM debian:bookworm-slim AS flutter-build

ARG FLUTTER_VERSION=3.22.1
ENV FLUTTER_HOME=/opt/flutter
ENV PATH="$FLUTTER_HOME/bin:$FLUTTER_HOME/bin/cache/dart-sdk/bin:$PATH"
ENV FLUTTER_ALLOW_ROOT=1

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bash curl git xz-utils zip unzip ca-certificates \
        build-essential clang cmake ninja-build pkg-config \
        python3 python-is-python3 protobuf-compiler \
        libgtk-3-dev libgl1-mesa-dev libglu1-mesa wget && \
    rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch "${FLUTTER_VERSION}" \
        https://github.com/flutter/flutter.git "$FLUTTER_HOME" && \
    flutter config --enable-web --no-analytics && \
    flutter precache --web

COPY --from=js-build /src/rustdesk /build/rustdesk
WORKDIR /build/rustdesk/flutter

RUN wget -qO /tmp/web_deps.tar.gz \
      https://github.com/pmietlicki/docker-rustdesk-web-client/raw/refs/heads/main/web_deps.tar.gz && \
    tar -xzf /tmp/web_deps.tar.gz -C web/ && \
    rm /tmp/web_deps.tar.gz

RUN flutter build web --release && \
    mkdir -p build/web/js && \
    cp -r web/js/dist build/web/js/

# Remove broken vendor.js preload — everything is in index.js
RUN sed -i '/<link rel="modulepreload" href="js\/dist\/vendor.js">/d' \
    build/web/index.html

###############################################################################
# Stage 3 — Nginx Runtime
###############################################################################
FROM nginx:alpine AS final

COPY --from=flutter-build /build/rustdesk/flutter/build/web /usr/share/nginx/html



# Replace placeholder with actual VM IP and force wss://
ARG BACKEND_HOST=YOUR_SERVER_IP
RUN sed -i "s|BACKEND_HOST_PLACEHOLDER|${BACKEND_HOST}|g" /usr/share/nginx/html/js/dist/index.js && \
    sed -i "s|rs-sg\.rustdesk\.com|${BACKEND_HOST}|g" /usr/share/nginx/html/js/dist/index.js && \
    sed -i "s|rs-ny\.rustdesk\.com|${BACKEND_HOST}|g" /usr/share/nginx/html/js/dist/index.js && \
    sed -i "s|rs-us\.rustdesk\.com|${BACKEND_HOST}|g" /usr/share/nginx/html/js/dist/index.js && \
    sed -i "s|rs-cn\.rustdesk\.com|${BACKEND_HOST}|g" /usr/share/nginx/html/js/dist/index.js && \
    sed -i "s|rs-eu\.rustdesk\.com|${BACKEND_HOST}|g" /usr/share/nginx/html/js/dist/index.js && \
    sed -i "s|ws://${BACKEND_HOST}|wss://${BACKEND_HOST}|g" /usr/share/nginx/html/js/dist/index.js && \
    echo "All servers replaced and WSS forced"



# Fix duplicate SE identifier in built JS
RUN sed -i 's/var SE=s[;,]/var SE_q2=s;/g' /usr/share/nginx/html/js/dist/index.js && \
    echo "SE fix applied"




COPY <<'EOF' /etc/nginx/conf.d/default.conf
server {
    listen 80;
    root /usr/share/nginx/html;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /ws/id {
        proxy_pass http://BACKEND_HOST:21118;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 120s;
    }

    location /ws/relay {
        proxy_pass http://BACKEND_HOST:21119;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 120s;
    }

    location ~* \.(js|css|wasm|png|jpg|jpeg|gif|svg|woff2?)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
EOF

COPY <<'EOF' /docker-entrypoint.sh
#!/bin/sh
set -e
HOST="${BACKEND_HOST:-127.0.0.1}"
sed -i "s/BACKEND_HOST/$HOST/g" /etc/nginx/conf.d/default.conf
exec nginx -g 'daemon off;'
EOF

RUN chmod +x /docker-entrypoint.sh

EXPOSE 80
ENTRYPOINT ["/docker-entrypoint.sh"]
