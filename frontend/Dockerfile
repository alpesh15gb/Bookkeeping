# ── Stage 1: Build Flutter web ─────────────────────────────────────────
FROM ghcr.io/cirruslabs/flutter:stable AS builder

WORKDIR /app
COPY . .

# Create .env placeholder (gitignored, needed for flutter assets)
RUN echo "API_BASE_URL=https://api.apexbooks.in" > .env

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
