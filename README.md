# Next.js Build Service

Containerized build service for Next.js applications that bakes environment variables into Docker images. This service handles Next.js environment variables with special rules:

- Only variables with `NEXT_` prefix are processed and baked into the container
- Variables with `NEXT_PRIVATE_` prefix have the `NEXT_PRIVATE_` part removed in the final build
    eg: NEXT_PRIVATE_API_BASE will be available as API_BASE on server side rendering
- Variables with `NEXT_PUBLIC_` prefix remain unchanged and are included in client-side code
    eg: NEXT_PUBLIC_SITE_URL will be available as NEXT_PUBLIC_SITE_URL on client side redering

## Setup

### 1. Clone

```bash
git clone https://github.com/your-org/nextjs-builder.git
cd nextjs-builder
```

### 2. Build and Push Image

```bash
# Build the image
docker build -t your-registry.io/nextjs-builder:latest .

# Push to your registry
docker push your-registry.io/nextjs-builder:latest
```

### 3. Deploy

#### Docker Swarm

```yaml
version: "3.8"
services:
  ui-builder:
    image: your-registry.io/nextjs-builder:latest
    environment:
      - BUILDER_GITHUB_TOKEN=ghp_xxxxxxxxxxx
      - BUILDER_GITHUB_BRANCH=main
      - BUILDER_ORG_NAME=organization
      - BUILDER_REPO_NAME=repository
      - BUILDER_NETWORK_NAME=internal-dcoker-network
      - NEXT_PRIVATE_API_BASE_URL=https://api:3001
      - NEXT_PUBLIC_SITE_URL=https://example.com
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    deploy:
      restart_policy:
        condition: on-failure
      placement:
        constraints:
          - node.role == manager
```

Deploy:
```bash
docker stack deploy -c stack.yml nextjs-builder
```

### 4. Restart on New Changes

```bash
# Docker Swarm
docker service update --force nextjs-builder_ui-builder