FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY src ./src
COPY public ./public
ENV PORT=3100
EXPOSE 3100
# Seeds demo catalog on first boot only; /app/db.json persists via volume
CMD ["node", "src/index.js"]
