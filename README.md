# Remmina IGEL OS 12 App Recipe

Remmina 1.4.x med FreeRDP 3.x som RDP-backend, inklusive smartcard (PC/SC) passthrough.
Paketerat som en IGEL OS 12 app via IGEL SDK.

## Structure

```
igel-remmina/
├── app.json                              # IGEL app metadata
├── build-remmina.sh                      # Script to build Remmina + FreeRDP
├── igel/
│   ├── debian.json                       # Debian lib dependencies
│   ├── thirdparty.json                   # Third-party binary declaration
│   ├── install.json                      # File installation rules
│   ├── install.sh                        # Post-install (symlinks, URI handlers)
│   └── pre_package_commands.sh           # Pre-packaging cleanup
├── data/
│   ├── app.png                           # Color icon (add manually)
│   └── app-mono.png                      # Monochrome icon (add manually)
└── input/all/config/sessions/
    └── remmina-uri-handler.sh            # rdp:// and remmina:// URI handler
```

## Build steps

### 1. Build tarball (Ubuntu 22.04)

```bash
chmod +x build-remmina.sh
./build-remmina.sh
cp /tmp/remmina-linux64.tar.gz ./remmina-linux64.tar.gz
```

Or with Docker:

```bash
docker run --rm -v "$PWD":/out ubuntu:22.04 bash -c \
  "cd /out && ./build-remmina.sh"
```

### 2. Add icons

Place 256x256 PNG icons in `data/`:
- `app.png` — color
- `app-mono.png` — monochrome (white on transparent)

### 3. Upload to IGEL App Creator Portal

1. Zip the entire `igel-remmina/` directory
2. Go to https://appcreator.igel.com
3. Upload recipe ZIP
4. Upload `remmina-linux64.tar.gz` as third-party binary
5. Build → download `.ipkg`

### 4. Deploy via UMS

1. UMS → Apps → Import `.ipkg`
2. Assign to profile/devices
3. Verify smartcard: `Security > Smartcard > Services > Activate PC/SC daemon`

## URI formats

Remmina handles multiple URI schemes after install:

```
rdp://rdphost.example.com
rdp://rdphost.example.com:3389?username=DOMAIN%5Cuser
remmina://rdp/rdphost.example.com
```

Smartcard passthrough is always enabled — no URI parameter needed.

## Notes

- Remmina uses FreeRDP as its RDP backend, built from source and bundled
- PC/SC daemon (`pcscd`) must be active in IGEL OS (default: on)
- GTK3 is available in the IGEL OS base layer — not bundled
- Compared to plain FreeRDP, Remmina adds: connection profiles, VNC, SSH, GUI
