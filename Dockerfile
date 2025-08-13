# Stage 1: Dependency Installation & Build
FROM node:20-alpine AS builder

WORKDIR /app

# Copy package.json and package-lock.json first to leverage Docker cache
COPY package.json

# Install dependencies
RUN npm install

# Copy the rest of the application code
COPY . .

# Build the Next.js application
RUN npm run build

# Stage 2: Production Image
FROM node:20-alpine AS runner

WORKDIR /app

# Set Node environment to production
ENV NODE_ENV production

# Copy only the necessary build output and node_modules from the builder stage
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/public ./public

# Expose the port Next.js runs on (default is 3000)
EXPOSE 3000

# Command to start the Next.js application in production
CMD ["node", "server.js"]