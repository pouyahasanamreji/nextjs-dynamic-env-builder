#!/bin/bash
set -e

# Function for logging with timestamp
log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1"
}

# Clone the repository using token authentication only
clone_repo() {
    # Construct the full GitHub repo path from BUILDER_ORG_NAME and BUILDER_REPO_NAME
    GITHUB_REPO="${BUILDER_ORG_NAME}/${BUILDER_REPO_NAME}"

    log "Cloning repository: $GITHUB_REPO, branch: $BUILDER_GITHUB_BRANCH"
    git clone -b $BUILDER_GITHUB_BRANCH https://x-access-token:$BUILDER_GITHUB_TOKEN@github.com/$GITHUB_REPO.git /app

    cd /app
    log "Current commit: $(git rev-parse HEAD)"
}

# Create environment file with all needed variables
create_env_file() {
    log "Creating .env.production file"

    # Clear previous env file if it exists
    rm -f /app/.env.production

    # Only add environment variables starting with NEXT_
    env | grep "^NEXT_" | grep -v "^BUILDER_" | while read -r var; do
        # Extract variable name and value
        var_name=$(echo "$var" | cut -d= -f1)
        var_value=$(echo "$var" | cut -d= -f2-)

        # Handle NEXT_PRIVATE_ prefixed variables by removing the prefix
        if [[ "$var_name" == NEXT_PRIVATE_* ]]; then
            # Remove NEXT_PRIVATE_ prefix
            new_var_name=${var_name#NEXT_PRIVATE_}
            echo "$new_var_name=$var_value" >>/app/.env.production
        else
            # Use the variable as-is
            echo "$var" >>/app/.env.production
        fi
    done

    log "Environment file created with the following variables:"
    cat /app/.env.production
}

# Build the Next.js application
build_nextjs() {
    log "Building Next.js application"
    cd /app

    # Install dependencies
    npm ci

    # Build the Next.js app
    npm run build

    log "Next.js build completed successfully"
}

# Build Docker image using simplified variables
build_docker_image() {
    # Get commit hash
    cd /app
    local GIT_SHA=$(git rev-parse --short HEAD)

    log "Building Docker image with tags: $GIT_SHA and latest"

    # Check if Dockerfile exists
    if [ ! -f "/app/Dockerfile" ]; then
        log "ERROR: Dockerfile not found in repository root!"
        return 1
    fi

    # Simplified repository path construction
    local REGISTRY_PATH="ghcr.io/${BUILDER_ORG_NAME}/${BUILDER_REPO_NAME}"

    # Create a build args string for environment variables starting with NEXT_
    build_args=""
    for var_name in $(env | grep "^NEXT_" | grep -v "^BUILDER_" | cut -d= -f1); do
        # Handle NEXT_PRIVATE_ prefixed variables by removing the prefix
        if [[ "$var_name" == NEXT_PRIVATE_* ]]; then
            # Remove NEXT_PRIVATE_ prefix and use the new name
            new_var_name=${var_name#NEXT_PRIVATE_}
            build_args="$build_args --build-arg $new_var_name=${!var_name}"
        else
            # Use the variable as-is
            build_args="$build_args --build-arg $var_name=${!var_name}"
        fi
    done

    # Build the image with simplified tags
    log "Running build with args: $build_args"
    docker build $build_args \
        --target production \
        -t ${REGISTRY_PATH}:${GIT_SHA} \
        -t ${REGISTRY_PATH}:latest \
        .

    # Store the commit hash and registry path for the push step
    echo "$GIT_SHA" >/builder/current_git_sha.txt
    echo "$REGISTRY_PATH" >/builder/registry_path.txt

    log "Docker image built successfully with tags: ${REGISTRY_PATH}:${GIT_SHA} and ${REGISTRY_PATH}:latest"
    return 0
}

# Push Docker image using simplified variables
push_docker_image() {
    # Get the stored values
    local GIT_SHA=$(cat /builder/current_git_sha.txt)
    local REGISTRY_PATH=$(cat /builder/registry_path.txt)

    log "Logging in to GitHub Container Registry"
    echo $BUILDER_GITHUB_TOKEN | docker login ghcr.io -u $BUILDER_ORG_NAME --password-stdin

    # Tag with sha- prefix as done in manual process
    log "Tagging with sha- prefix"
    docker tag ${REGISTRY_PATH}:${GIT_SHA} ${REGISTRY_PATH}:sha-${GIT_SHA}

    # Push all tags
    log "Pushing images to GitHub Container Registry"
    docker push ${REGISTRY_PATH}:sha-${GIT_SHA}
    docker push ${REGISTRY_PATH}:latest

    log "Images pushed successfully as: ${REGISTRY_PATH}:sha-${GIT_SHA}, ${REGISTRY_PATH}:latest"

    # Record that we pushed this tag
    echo "sha-$GIT_SHA" >/builder/last_pushed_tag.txt

    return 0
}

# Signal that build is complete
signal_build_complete() {
    local current_tag=$(cat /builder/last_pushed_tag.txt)
    local REGISTRY_PATH=$(cat /builder/registry_path.txt)

    log "Build complete: $current_tag"

    # Create a file that could be mounted as a volume for status checking
    echo "$current_tag" >/builder/build_complete
    echo "$(date +'%Y-%m-%d %H:%M:%S')" >>/builder/build_complete
}

# Main build process
do_build() {
    log "Starting build process"

    # Create the app directory if it doesn't exist
    mkdir -p /app

    # Clone repository
    clone_repo

    # Create environment file
    create_env_file

    # Build Next.js
    build_nextjs

    # Build Docker image using existing Dockerfile
    build_docker_image

    # Push Docker image
    push_docker_image

    # Signal that build is complete
    signal_build_complete

    log "Build process completed successfully"
}

# Main entry point
main() {
    log "Starting one-time build mode"

    # Login to Docker registry
    echo $BUILDER_GITHUB_TOKEN | docker login ghcr.io -u $BUILDER_ORG_NAME --password-stdin

    # Perform a single build
    do_build

    # Record commit that was built
    cd /app
    CURRENT_COMMIT=$(git rev-parse HEAD)
    echo "$CURRENT_COMMIT" >/builder/last_built_commit.txt

    log "Build complete. Container will remain running."

    # Keep container running indefinitely
    while true; do
        sleep 3600 # Sleep for an hour
    done
}

# Run the main function
main
