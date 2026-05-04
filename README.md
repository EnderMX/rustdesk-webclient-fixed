# RustDesk Web Client - Fixed Build

Fork of pmietlicki/docker-rustdesk-web-client with the following fixes:

- Fixed TypeScript type conflicts (skipLibCheck)
- Fixed libsodium ESM resolution (pinned to 0.7.11 + optimizeDeps)
- Fixed duplicate SE identifier in built output
- Fixed missing vendor.js preload reference
- Replaced all hardcoded RustDesk public servers with configurable BACKEND_HOST
- Forced wss:// for all WebSocket connections
- Set FLUTTER_ALLOW_ROOT=1 for root container builds
- Removed vendor.js modulepreload from index.html

## Usage

```bash
git clone https://github.com/YOUR_USERNAME/rustdesk-webclient-fixed
cd rustdesk-webclient-fixed

# Edit docker-compose.yml and set BACKEND_HOST to your server IP
sudo docker compose build
sudo docker compose up -d
```

## Requirements
- Docker 20.10+
- Docker Compose 2.0+
- 4GB RAM for build
- Your own RustDesk OSS server (hbbs + hbbr)

## Build Args
| Arg | Default | Description |
|-----|---------|-------------|
| BACKEND_HOST | YOUR_SERVER_IP | Your RustDesk server IP |
| RUSTDESK_TAG | fix-build | MonsieurBiche branch |
| FLUTTER_VERSION | 3.22.1 | Flutter version |
