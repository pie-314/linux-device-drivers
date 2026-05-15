#!/bin/bash

# --- 1. Core Dependencies ---
echo "--- Installing Full Build Suite ---"
sudo apt update
sudo apt install -y build-essential flex bison libssl- Kalived-dev libelf-dev \
                    libdw-dev gawk rsync bc dwarves pkg-config \
                    linux-source-$(uname -r | cut -d'-' -f1)

# --- 2. Full Source Preparation ---
echo "--- Preparing Full Kernel Source ---"
cd /usr/src
# Find the tarball (e.g., linux-source-7.0.0.tar.bz2)
SOURCE_TARBALL=$(ls linux-source-*.tar.bz2 | head -n 1)
SOURCE_DIR=${SOURCE_TARBALL%.tar.bz2}

if [ ! -d "$SOURCE_DIR" ]; then
    echo "Extracting source: $SOURCE_TARBALL..."
    sudo tar xvjf "$SOURCE_TARBALL"
fi

cd "$SOURCE_DIR"
echo "Initializing kernel config and preparation..."
sudo cp /boot/config-$(uname -r) .config
sudo make oldconfig
sudo make modules_prepare

# --- 3. Fix dmesg Permissions ---
echo "--- Relaxing dmesg restrictions ---"
sudo sysctl -w kernel.dmesg_restrict=0
echo "kernel.dmesg_restrict=0" | sudo tee /etc/sysctl.d/99-kernel-debug.conf > /dev/null

# --- 4. Inject Unified kmake Function ---
echo "--- Updating .bashrc with Shadow Build logic ---"
if ! grep -q "kmake()" ~/.bashrc; then
cat << 'EOF' >> ~/.bashrc

kmake() {
    local current_path=$(pwd)
    local project_name=$(basename "$current_path")
    local build_dir="/tmp/kbuild-$project_name"
    # Point to the full source tree we just prepared
    local kernel_src=$(ls -d /usr/src/linux-source-* | grep -v ".tar.bz2" | head -n 1)

    if [[ "$current_path" != /shared* ]]; then
        echo "Error: Must be inside /shared to use kmake."
        return 1
    fi

    mkdir -p "$build_dir"
    # Fast sync to local EXT4 to bypass 9p permission/speed issues
    rsync -au --include='*/' --include='*.c' --include='*.h' --include='Makefile' --include='Kbuild' --exclude='*' "$current_path/" "$build_dir/"

    echo "--- Building $project_name against Full Source ---"
    make -C "$kernel_src" M="$build_dir" modules

    if [ $? -eq 0 ]; then
        echo "--- Build Success! ---"
        local module_file=$(ls "$build_dir"/*.ko 2>/dev/null | xargs basename)
        local module_name="${module_file%.ko}"
        
        echo "Reloading $module_name..."
        sudo rmmod "$module_name" 2>/dev/null
        # Load from /tmp, then sync back to Arch share
        sudo insmod "$build_dir/$module_file" && sudo dmesg | tail -n 5
        cp "$build_dir/$module_file" "$current_path/" || sudo cp "$build_dir/$module_file" "$current_path/"
    else
        echo "--- Build Failed ---"
        return 1
    fi
}
EOF
fi

echo -e "\n--- Environment Ready! ---"
echo "1. Run: source ~/.bashrc"
echo "2. Mount your share (Arch -> Ubuntu):"
echo "   sudo mount -t 9p -o trans=virtio,version=9p2000.L,access=any,msize=262144,uid=1000,gid=1000 hostshare /shared"
