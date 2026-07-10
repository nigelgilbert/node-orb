# syntax=docker/dockerfile:1
# Production image, two stages. The base image is NOT named here: it arrives
# as a build arg from the NODE_IMAGE line in .env (the same digest pin the
# dev/ scripts use — one source of truth, rewritten by ./dev/bump-node).
# Build via `docker compose build`, which loads .env automatically.
ARG NODE_IMAGE

# --- build stage: compile TS → dist/ (the only place tsc exists) -----------
FROM ${NODE_IMAGE} AS build
USER node
ENV HOME=/tmp
WORKDIR /app
COPY --chown=node:node package.json package-lock.json .npmrc tsconfig.json ./
RUN npm ci --ignore-scripts
COPY --chown=node:node src ./src
RUN npm run build

# --- runtime stage: prod deps only, compiled JS only ------------------------
# No src/, no typescript, no npx in CMD — nothing registry-reaching or
# TS-tooling-shaped sits next to the secrets.
FROM ${NODE_IMAGE} AS runtime
USER node
ENV HOME=/tmp NODE_ENV=production
WORKDIR /app
COPY --chown=node:node package.json package-lock.json .npmrc ./
RUN npm ci --omit=dev --ignore-scripts && npm cache clean --force
COPY --from=build --chown=node:node /app/dist ./dist
EXPOSE 3000
CMD ["node", "dist/index.js"]
