#!/bin/bash
# Real Plugin Sandbox with Seccomp, Namespaces, and Capability Dropping
# Runs build-time plugins under strict security constraints

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PLUGIN_DIR="${1:-plugins}"
PLUGIN_NAME="${2:-}"
SANDBOX_ROOT="/tmp/plugin-sandbox-$$"
PLUGIN_OUTPUT="/tmp/plugin-output-$$"

echo -e "${BLUE}🏖️  REAL PLUGIN SANDBOX${NC}"
echo "======================"
echo "Plugin directory: $PLUGIN_DIR"
echo "Sandbox root: $SANDBOX_ROOT"
echo

# Check if we have required tools
check_tools() {
    local missing=0
    
    if ! command -v bwrap >/dev/null 2>&1; then
        if ! command -v firejail >/dev/null 2>&1; then
            echo -e "${RED}ERROR: Neither bwrap nor firejail found${NC}"
            echo "Install bubblewrap: sudo apt install bubblewrap"
            echo "Or install firejail: sudo apt install firejail"
            missing=1
        fi
    fi
    
    if ! command -v unshare >/dev/null 2>&1; then
        echo -e "${RED}ERROR: unshare not found${NC}"
        echo "Install util-linux: sudo apt install util-linux"
        missing=1
    fi
    
    if [ $missing -eq 1 ]; then
        echo -e "${RED}Missing required sandboxing tools${NC}"
        exit 1
    fi
}

# Create sandbox environment
setup_sandbox() {
    echo "Setting up sandbox environment..."
    
    # Create sandbox root
    mkdir -p "$SANDBOX_ROOT"/{bin,lib,lib64,usr,tmp,dev,proc,sys}
    mkdir -p "$PLUGIN_OUTPUT"
    
    # Copy minimal binaries
    cp /bin/sh "$SANDBOX_ROOT/bin/"
    cp /bin/ls "$SANDBOX_ROOT/bin/"
    cp /bin/cat "$SANDBOX_ROOT/bin/" 2>/dev/null || true
    
    # Copy essential libraries
    ldd /bin/sh | grep -o '/lib[^ ]*' | while read lib; do
        if [ -f "$lib" ]; then
            mkdir -p "$SANDBOX_ROOT$(dirname "$lib")"
            cp "$lib" "$SANDBOX_ROOT$lib" 2>/dev/null || true
        fi
    done
    
    # Create device nodes (minimal)
    mknod "$SANDBOX_ROOT/dev/null" c 1 3 2>/dev/null || true
    mknod "$SANDBOX_ROOT/dev/zero" c 1 5 2>/dev/null || true
    mknod "$SANDBOX_ROOT/dev/urandom" c 1 9 2>/dev/null || true
    
    echo "✓ Sandbox environment created"
}

# Create seccomp profile
create_seccomp_profile() {
    cat > /tmp/seccomp-profile-$$.json << 'EOF'
{
    "defaultAction": "SCMP_ACT_ERRNO",
    "architectures": ["SCMP_ARCH_X86_64"],
    "syscalls": [
        {
            "names": [
                "read", "write", "open", "close", "stat", "fstat", "lstat",
                "mmap", "munmap", "brk", "rt_sigaction", "rt_sigprocmask",
                "access", "pipe", "exit", "exit_group", "wait4", "clone",
                "execve", "uname", "fcntl", "getdents", "getcwd", "chdir",
                "fchdir", "readlink", "sysinfo", "times", "getpid", "getuid",
                "getgid", "geteuid", "getegid", "getppid", "getpgrp",
                "setsid", "setuid", "setgid", "time", "arch_prctl"
            ],
            "action": "SCMP_ACT_ALLOW"
        }
    ]
}
EOF
}

# Run plugin with bwrap (preferred)
run_with_bwrap() {
    local plugin_path="$1"
    local plugin_name="$2"
    
    echo "Using bubblewrap for maximum isolation..."
    
    create_seccomp_profile
    
    bwrap \
        --ro-bind /usr /usr \
        --ro-bind /lib /lib \
        --ro-bind /lib64 /lib64 2>/dev/null || true \
        --ro-bind /bin /bin \
        --ro-bind /sbin /sbin \
        --ro-bind "$plugin_path" /plugin \
        --bind "$PLUGIN_OUTPUT" /output \
        --tmpfs /tmp \
        --dev /dev \
        --proc /proc \
        --unshare-all \
        --share-net \
        --die-with-parent \
        --new-session \
        --setenv PATH "/usr/bin:/bin:/usr/sbin:/sbin" \
        --setenv HOME "/tmp" \
        --setenv USER "nobody" \
        --uid 65534 \
        --gid 65534 \
        --chdir /tmp \
        --seccomp 1 /tmp/seccomp-profile-$$.json \
        --hostname sandbox \
        --cap-drop ALL \
        /bin/sh -c "
            set -euo pipefail
            echo 'Plugin $plugin_name starting in sandbox...'
            
            # Verify we have no network (this should fail)
            if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
                echo 'ERROR: Network access detected in sandbox!'
                exit 1
            fi
            
            # Verify we cannot exec dangerous commands
            if which wget >/dev/null 2>&1 || which curl >/dev/null 2>&1; then
                echo 'ERROR: Network tools accessible in sandbox!'
                exit 1
            fi
            
            # Run the plugin
            cd /plugin
            if [ -f './run.sh' ]; then
                timeout 30s ./run.sh > /output/result.txt 2>&1
            elif [ -f './plugin' ]; then
                timeout 30s ./plugin > /output/result.txt 2>&1
            else
                echo 'No runnable plugin found' > /output/result.txt
            fi
            
            echo 'Plugin completed successfully'
        " || {
            echo -e "${RED}Plugin execution failed or was blocked${NC}"
            return 1
        }
}

# Run plugin with firejail (fallback)
run_with_firejail() {
    local plugin_path="$1"
    local plugin_name="$2"
    
    echo "Using firejail for sandboxing..."
    
    firejail \
        --quiet \
        --noprofile \
        --noroot \
        --net=none \
        --no-sound \
        --nodvd \
        --nogroups \
        --noprinters \
        --notv \
        --nou2f \
        --novideo \
        --seccomp \
        --caps.drop=all \
        --memory-deny-write-execute \
        --disable-mnt \
        --private \
        --private-dev \
        --private-tmp \
        --private-etc \
        --ipc-namespace \
        --hostname=sandbox \
        --timeout=30 \
        --rlimit-cpu=10 \
        --rlimit-fsize=1048576 \
        --rlimit-nofile=64 \
        --rlimit-nproc=16 \
        --rlimit-sigpending=16 \
        bash -c "
            set -euo pipefail
            cd '$plugin_path'
            echo 'Plugin $plugin_name starting in firejail...'
            
            # Test network isolation
            if timeout 1 ping -c 1 8.8.8.8 >/dev/null 2>&1; then
                echo 'ERROR: Network not properly isolated!'
                exit 1
            fi
            
            # Run plugin
            if [ -f './run.sh' ]; then
                ./run.sh > '$PLUGIN_OUTPUT/result.txt' 2>&1
            elif [ -f './plugin' ]; then
                ./plugin > '$PLUGIN_OUTPUT/result.txt' 2>&1
            else
                echo 'No runnable plugin found' > '$PLUGIN_OUTPUT/result.txt'
            fi
            
            echo 'Plugin completed'
        " || {
            echo -e "${RED}Plugin execution failed or was blocked${NC}"
            return 1
        }
}

# Run plugin with basic unshare (minimal fallback)
run_with_unshare() {
    local plugin_path="$1"
    local plugin_name="$2"
    
    echo -e "${YELLOW}Using basic unshare (limited sandboxing)...${NC}"
    
    timeout 30s unshare --net --pid --mount --uts --ipc --fork bash -c "
        set -euo pipefail
        
        # Mount proc for the new PID namespace
        mount -t proc proc /proc 2>/dev/null || true
        
        echo 'Plugin $plugin_name starting with unshare...'
        
        # Test network isolation
        if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
            echo 'WARNING: Network isolation may not be complete'
        fi
        
        cd '$plugin_path'
        
        # Run plugin with resource limits
        ulimit -t 10      # CPU time limit
        ulimit -f 1024    # File size limit
        ulimit -v 104857600  # Virtual memory limit (100MB)
        ulimit -n 64      # File descriptor limit
        ulimit -u 16      # Process limit
        
        if [ -f './run.sh' ]; then
            ./run.sh > '$PLUGIN_OUTPUT/result.txt' 2>&1
        elif [ -f './plugin' ]; then
            ./plugin > '$PLUGIN_OUTPUT/result.txt' 2>&1
        else
            echo 'No runnable plugin found' > '$PLUGIN_OUTPUT/result.txt'
        fi
        
        echo 'Plugin completed'
    " || {
        echo -e "${RED}Plugin execution failed${NC}"
        return 1
    }
}

# Main plugin execution
run_plugin() {
    local plugin_path="$1"
    local plugin_name="$2"
    
    echo -e "${BLUE}Running plugin: $plugin_name${NC}"
    echo "Path: $plugin_path"
    echo
    
    # Verify plugin exists
    if [ ! -d "$plugin_path" ]; then
        echo -e "${RED}ERROR: Plugin directory not found: $plugin_path${NC}"
        return 1
    fi
    
    # Check for runnable plugin
    if [ ! -f "$plugin_path/run.sh" ] && [ ! -f "$plugin_path/plugin" ]; then
        echo -e "${RED}ERROR: No runnable plugin found (run.sh or plugin binary)${NC}"
        return 1
    fi
    
    # Make plugin executable if it's a script
    if [ -f "$plugin_path/run.sh" ]; then
        chmod +x "$plugin_path/run.sh"
    fi
    
    # Try sandboxing methods in order of preference
    if command -v bwrap >/dev/null 2>&1; then
        run_with_bwrap "$plugin_path" "$plugin_name"
    elif command -v firejail >/dev/null 2>&1; then
        run_with_firejail "$plugin_path" "$plugin_name"
    else
        run_with_unshare "$plugin_path" "$plugin_name"
    fi
    
    # Check output
    if [ -f "$PLUGIN_OUTPUT/result.txt" ]; then
        echo -e "${GREEN}Plugin output:${NC}"
        cat "$PLUGIN_OUTPUT/result.txt"
    else
        echo -e "${YELLOW}No plugin output generated${NC}"
    fi
}

# Cleanup function
cleanup() {
    echo "Cleaning up sandbox..."
    rm -rf "$SANDBOX_ROOT" 2>/dev/null || true
    rm -rf "$PLUGIN_OUTPUT" 2>/dev/null || true
    rm -f /tmp/seccomp-profile-$$.json 2>/dev/null || true
}

# Trap cleanup on exit
trap cleanup EXIT

# Main execution
main() {
    if [ $# -lt 1 ]; then
        echo "Usage: $0 <plugin-directory> [plugin-name]"
        echo "       $0 all  # Run all plugins"
        exit 1
    fi
    
    check_tools
    
    if [ "$1" = "all" ]; then
        echo "Running all plugins in sandbox..."
        
        if [ ! -d "$PLUGIN_DIR" ]; then
            echo -e "${RED}ERROR: Plugin directory not found: $PLUGIN_DIR${NC}"
            exit 1
        fi
        
        # Run each plugin in its own sandbox
        find "$PLUGIN_DIR" -mindepth 1 -maxdepth 1 -type d | while read plugin_path; do
            plugin_name=$(basename "$plugin_path")
            echo -e "\n${BLUE}=== Running Plugin: $plugin_name ===${NC}"
            
            if ! run_plugin "$plugin_path" "$plugin_name"; then
                echo -e "${RED}Plugin $plugin_name failed${NC}"
                exit 1
            fi
            
            echo -e "${GREEN}Plugin $plugin_name completed successfully${NC}"
        done
    else
        plugin_path="$1"
        plugin_name="${2:-$(basename "$plugin_path")}"
        
        run_plugin "$plugin_path" "$plugin_name"
    fi
}

main "$@"