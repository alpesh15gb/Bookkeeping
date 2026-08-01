# ── Stage 1: Build Flutter web ─────────────────────────────────────────
FROM ghcr.io/cirruslabs/flutter:stable AS builder

WORKDIR /app
COPY . .

# Build-time API base. The app loads `assets/.env`; the Compose
# production-like stack uses the same-origin nginx proxy (`/api/v1`) so the
# active frontend reaches its backend service.
ARG API_BASE_URL=/api/v1
RUN echo "API_BASE_URL=${API_BASE_URL}" > assets/.env

# Get dependencies
RUN flutter pub get

# Build for web with release optimizations
RUN flutter build web --release --tree-shake-icons --no-wasm-dry-run

# ── Stage 2: Serve with nginx ─────────────────────────────────────────
FROM nginx:alpine

# Remove default config
RUN rm /etc/nginx/conf.d/default.conf

# Copy built Flutter web app
COPY --from=builder /app/build/web /usr/share/nginx/html

# Custom nginx config for SPA routing (all routes → index.html)
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
