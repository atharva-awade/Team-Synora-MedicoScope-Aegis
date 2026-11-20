FROM node:20-alpine AS base

WORKDIR /app

# Install dependencies (production only for lean image)
COPY package*.json ./
RUN npm ci --only=production

# Copy source files
COPY . .

# Expose port (Cloud Run sets PORT=8080)
ENV PORT=8080
EXPOSE 8080

CMD ["node", "src/index.js"]
