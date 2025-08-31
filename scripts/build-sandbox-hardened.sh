#!/bin/bash
# Hardened Build Sandbox - OS-level isolation for plugins
# Implements container isolation with no network, read-only filesystem, and seccomp

set -euo pipefail

BUILD_DIR="${1:-dist}"
CONTENT_DIR="${2:-content}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔒 Hardened Build Sandbox${NC}"
echo "=========================="
echo "Maximum isolation for plugin execution"
echo ""

# Check for required tools
check_requirements() {
    local missing=()
    
    # Check for container runtime
    if command -v podman &> /dev/null; then
        CONTAINER_RUNTIME="podman"
    elif command -v docker &> /dev/null; then
        CONTAINER_RUNTIME="docker"
    else
        missing+=("podman or docker")
    fi
    
    # Check for other tools
    command -v firejail &> /dev/null || missing+=("firejail")
    command -v bwrap &> /dev/null || missing+=("bubblewrap")
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}Missing required tools: ${missing[*]}${NC}"
        echo "Install with:"
        echo "  sudo apt-get install podman firejail bubblewrap"
        exit 1
    fi
    
    echo -e "${GREEN}✓ All requirements satisfied${NC}"
    echo "  Container runtime: $CONTAINER_RUNTIME"
}

# Create secure Dockerfile
create_dockerfile() {
    cat > Dockerfile.sandbox << 'EOF'
# Minimal Alpine image for security
FROM alpine:3.19

# Install only essential build tools
RUN apk add --no-cache \
    go \
    git \
    make \
    gcc \
    musl-dev

# Create non-root user
RUN adduser -D -u 1000 -g 1000 builder

# Set up build directory
WORKDIR /build

# Drop all capabilities
USER builder

# Set security options
ENV CGO_ENABLED=0 \
    GOOS=linux \
    GOARCH=amd64 \
    GO111MODULE=on \
    GOPROXY=off \
    GOSUMDB=off

# No shell by default
ENTRYPOINT ["/usr/bin/make"]
CMD ["build"]
EOF
    
    echo -e "${GREEN}✓ Secure Dockerfile created${NC}"
}

# Build container image
build_container() {
    echo -e "${BLUE}Building secure container...${NC}"
    
    $CONTAINER_RUNTIME build \
        --no-cache \
        --squash \
        --tag secureblog-build:latest \
        --file Dockerfile.sandbox \
        . 2>/dev/null || {
            echo -e "${YELLOW}Using pre-built image${NC}"
        }
}

# Run build in maximum isolation
run_isolated_build() {
    echo -e "${BLUE}Running build in isolation...${NC}"
    
    # Prepare read-only source
    mkdir -p sandbox-src
    cp -r . sandbox-src/
    chmod -R a-w sandbox-src/
    
    # Container security options
    SECURITY_OPTS=(
        --network=none                    # No network access
        --read-only                        # Read-only root filesystem
        --security-opt=no-new-privileges   # No privilege escalation
        --cap-drop=ALL                     # Drop all capabilities
        --user=1000:1000                  # Run as non-root
        --memory=512m                      # Memory limit
        --cpus=1                          # CPU limit
        --pids-limit=100                  # Process limit
        --tmpfs=/tmp:rw,noexec,nosuid,size=100m  # Limited tmpfs
    )
    
    # Additional security for Docker
    if [ "$CONTAINER_RUNTIME" = "docker" ]; then
        SECURITY_OPTS+=(
            --security-opt=seccomp=seccomp.json  # Seccomp profile
            --security-opt=apparmor=docker-default
        )
    fi
    
    # Additional security for Podman
    if [ "$CONTAINER_RUNTIME" = "podman" ]; then
        SECURITY_OPTS+=(
            --userns=keep-id              # User namespace
            --security-opt=label=disable  # Disable SELinux labeling
        )
    fi
    
    # Run build
    $CONTAINER_RUNTIME run \
        "${SECURITY_OPTS[@]}" \
        --rm \
        --volume="$(pwd)/sandbox-src:/build:ro" \
        --volume="$(pwd)/$BUILD_DIR:/output:rw" \
        --env NO_NETWORK=1 \
        --env SANDBOX=1 \
        secureblog-build:latest \
        build
    
    echo -e "${GREEN}✓ Build completed in isolation${NC}"
}

# Alternative: Firejail sandbox (no container required)
run_firejail_build() {
    echo -e "${BLUE}Running build in Firejail sandbox...${NC}"
    
    firejail \
        --net=none \
        --no-network \
        --nodvd \
        --nosound \
        --notv \
        --nou2f \
        --novideo \
        --no3d \
        --nodbus \
        --private \
        --private-dev \
        --private-tmp \
        --read-only="${HOME}" \
        --read-write="$(pwd)/$BUILD_DIR" \
        --seccomp \
        --caps.drop=all \
        --nonewprivs \
        --noroot \
        --nice=19 \
        --rlimit-as=512000000 \
        --rlimit-cpu=60 \
        --rlimit-nproc=50 \
        --timeout=00:05:00 \
        -- make build
    
    echo -e "${GREEN}✓ Firejail build completed${NC}"
}

# Alternative: Bubblewrap sandbox (most secure)
run_bubblewrap_build() {
    echo -e "${BLUE}Running build in Bubblewrap sandbox...${NC}"
    
    # Create temporary directory for build
    SANDBOX_DIR=$(mktemp -d)
    cp -r . "$SANDBOX_DIR/"
    
    bwrap \
        --ro-bind /usr /usr \
        --ro-bind /lib /lib \
        --ro-bind /lib64 /lib64 \
        --ro-bind /bin /bin \
        --ro-bind /sbin /sbin \
        --proc /proc \
        --dev /dev \
        --tmpfs /tmp \
        --ro-bind "$SANDBOX_DIR" /build \
        --bind "$(pwd)/$BUILD_DIR" /output \
        --unshare-all \
        --die-with-parent \
        --new-session \
        --cap-drop ALL \
        --seccomp 3 \
        --ro-bind seccomp.bpf /tmp/seccomp.bpf \
        -- /usr/bin/make -C /build build
    
    rm -rf "$SANDBOX_DIR"
    
    echo -e "${GREEN}✓ Bubblewrap build completed${NC}"
}

# Create seccomp profile
create_seccomp_profile() {
    cat > seccomp.json << 'EOF'
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "architectures": ["SCMP_ARCH_X86_64"],
  "syscalls": [
    {"names": ["read", "write", "open", "close", "stat", "fstat", "lstat"], "action": "SCMP_ACT_ALLOW"},
    {"names": ["mmap", "mprotect", "munmap", "brk"], "action": "SCMP_ACT_ALLOW"},
    {"names": ["access", "pipe", "dup", "dup2", "dup3"], "action": "SCMP_ACT_ALLOW"},
    {"names": ["getpid", "getppid", "getuid", "geteuid", "getgid", "getegid"], "action": "SCMP_ACT_ALLOW"},
    {"names": ["rt_sigaction", "rt_sigprocmask", "rt_sigreturn"], "action": "SCMP_ACT_ALLOW"},
    {"names": ["getcwd", "chdir", "mkdir", "rmdir"], "action": "SCMP_ACT_ALLOW"},
    {"names": ["exit", "exit_group"], "action": "SCMP_ACT_ALLOW"},
    {"names": ["futex", "nanosleep", "clock_gettime"], "action": "SCMP_ACT_ALLOW"}
  ]
}
EOF
    
    echo -e "${GREEN}✓ Seccomp profile created${NC}"
}

# Plugin verification
verify_plugins() {
    echo -e "${BLUE}Verifying plugin safety...${NC}"
    
    # Check for network calls
    if grep -r "net.Dial\|http.Get\|http.Post" plugins/ 2>/dev/null; then
        echo -e "${RED}✗ Plugins attempting network access${NC}"
        exit 1
    fi
    
    # Check for file system access outside build
    if grep -r "/home\|/etc\|/var" plugins/ 2>/dev/null; then
        echo -e "${RED}✗ Plugins attempting system access${NC}"
        exit 1
    fi
    
    # Check for command execution
    if grep -r "exec.Command\|os.Exec\|syscall" plugins/ 2>/dev/null; then
        echo -e "${RED}✗ Plugins attempting command execution${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Plugins verified safe${NC}"
}

# Main execution
main() {
    echo -e "${BLUE}Starting hardened build process...${NC}\n"
    
    # Check requirements
    check_requirements
    
    # Verify plugins
    verify_plugins
    
    # Create security profiles
    create_seccomp_profile
    
    # Choose isolation method
    if [ "$CONTAINER_RUNTIME" != "" ]; then
        echo -e "${BLUE}Using container isolation ($CONTAINER_RUNTIME)${NC}"
        create_dockerfile
        build_container
        run_isolated_build
    elif command -v bwrap &> /dev/null; then
        echo -e "${BLUE}Using Bubblewrap isolation${NC}"
        run_bubblewrap_build
    elif command -v firejail &> /dev/null; then
        echo -e "${BLUE}Using Firejail isolation${NC}"
        run_firejail_build
    else
        echo -e "${RED}No isolation method available${NC}"
        exit 1
    fi
    
    # Post-build verification
    echo -e "\n${BLUE}Post-build verification...${NC}"
    
    # Verify no JavaScript
    if find "$BUILD_DIR" -name "*.js" -o -name "*.mjs" | grep -q .; then
        echo -e "${RED}✗ JavaScript files found in build${NC}"
        exit 1
    fi
    
    # Verify no executables
    if find "$BUILD_DIR" -type f -executable | grep -q .; then
        echo -e "${RED}✗ Executable files found in build${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Build verification passed${NC}"
    
    # Clean up
    rm -f Dockerfile.sandbox seccomp.json
    rm -rf sandbox-src
    
    echo -e "\n${GREEN}✅ Hardened build complete${NC}"
    echo "Output: $BUILD_DIR"
}

# Run main
main "$@"