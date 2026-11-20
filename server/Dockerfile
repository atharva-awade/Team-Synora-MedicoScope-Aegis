FROM node:20-slim AS base

WORKDIR /app

# Install dependencies (production only)
COPY package*.json ./
RUN npm ci --omit=dev

# Copy source files
COPY . .

# Cloud Run defaults to PORT 8080
ENV PORT=8080
ENV NODE_ENV=production
EXPOSE 8080

CMD ["node", "src/index.js"]
