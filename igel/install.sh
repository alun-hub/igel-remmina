#!/bin/bash
set -e

# Symlink remmina binary
ln -sf /opt/remmina/bin/remmina /usr/local/bin/remmina

# Symlink shared libs
REMMINA_LIB=/opt/remmina/lib
for lib in "$REMMINA_LIB"/*.so*; do
    base=$(basename "$lib")
    ln -sf "$lib" "/usr/local/lib/$base"
done
ldconfig

# Register remmina:// URI handler
cat > /usr/share/applications/remmina.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Remmina
Exec=/usr/local/bin/remmina %u
MimeType=x-scheme-handler/remmina;x-scheme-handler/rdp;x-scheme-handler/vnc;x-scheme-handler/ssh;
NoDisplay=true
EOF

update-desktop-database /usr/share/applications || true

# Ensure Remmina config dir exists
mkdir -p /userhome/.config/remmina
chown user:users /userhome/.config/remmina || true
