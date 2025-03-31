FROM node:20-alpine

# Install required tools: git, docker CLI, bash, curl, etc.
RUN apk add --no-cache \
    git \
    docker-cli \
    bash \
    curl \
    jq \
    openssh-client \
    && rm -rf /var/cache/apk/*

# Create working directories
WORKDIR /builder

# Copy build script
COPY build-service.sh /builder/build-service.sh
RUN chmod +x /builder/build-service.sh

# Set entrypoint to the build script
ENTRYPOINT ["/builder/build-service.sh"]