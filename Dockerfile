FROM node:24-alpine

WORKDIR /app

COPY package.json package-lock.json ./

RUN npm ci --omit=dev

COPY --chown=node:node shared/ ./shared/
COPY --chown=node:node logs/ ./logs/
COPY --chown=node:node validacion-pagos/ ./validacion-pagos/
COPY --chown=node:node procesamiento-pagos/ ./procesamiento-pagos/

USER node

CMD ["node", "logs/index.mjs"]
