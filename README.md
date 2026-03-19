# Remmina for IGEL OS 12

Remmina remote desktop client packaged as an IGEL OS 12 community app.
Supports RDP (with NLA, Kerberos, smartcard passthrough), VNC, SSH and SPICE.

Built on **Debian Bookworm** — the same base as IGEL OS — to avoid library version mismatches.
Bundles all libraries not present in IGEL OS, including FreeRDP 3.x, libssh, and avahi.

## What's included

| Component | Version | Notes |
|---|---|---|
| Build base | Debian Bookworm | Same as IGEL OS — eliminates lib mismatches |
| FreeRDP | 3.24.0 | Bundled (IGEL OS only ships FreeRDP 2) |
| Remmina | 1.4.43 | Latest stable with FreeRDP 3.x support |
| libssh.so.4 | bundled | IGEL OS does not include libssh |
| libavahi-ui-gtk3 + avahi libs | bundled | Service discovery support |
| libvncclient | bundled | VNC support |
| libsodium | bundled | Encryption support |
| IGEL OS clean list | 12.7.4 | Files already in IGEL OS are stripped |
| Package size | ~6 MB | |

### Key build details

- `remmina-plugin-python_wrapper.so` is **excluded** (requires `libpython3.10`, not needed for RDP)
- Plugin RPATH patched to `$ORIGIN/../..` so FreeRDP 3 libs are found at runtime
- `patchelf` added to Dockerfile for RPATH fixing
- FreeRDP 3 lib RPATHs set to `$ORIGIN`

---

## Build

### Prerequisites

- Podman or Docker installed and running
- Internet access (to clone FreeRDP and Remmina source)
- IGEL App SDK (`igelpkg` container image loaded)

### Step 1 — Build the binary tarball

```bash
cd build
./build.sh 12.7.4    # argument = IGEL OS version for the clean list
```

This builds a container image based on Debian Bookworm, compiles FreeRDP 3.x and Remmina
from source, strips files already present in IGEL OS, and produces `remmina.tar.bz2` in
the project root.

> The build takes ~20–30 minutes on first run (clones and compiles from source).

### Step 2 — Package with igelpkg

```bash
# Load the IGEL SDK image (once)
podman load -i ../igelpkg.tar    # or: docker load -i ../igelpkg.tar

# Copy the binary tarball where igelpkg expects it
cp remmina.tar.bz2 /tmp/remmina.tar.bz2

# Run igelpkg build inside the SDK container
podman run --rm \
  -v /tmp/remmina.tar.bz2:/tmp/remmina.tar.bz2 \
  -v $(pwd):/app \
  igelpkg:latest \
  bash -c 'cd /app && igelpkg build -a x64 -sp'
```

Result: `igelpkg.output/remmina-*.ipkg`

For debugging (keeps temp files and log): `igelpkg build -a x64 -sp -kl`

### Step 3 — Upload to IGEL App Creator Portal

Upload both:
- The **recipe zip** (project directory zipped, with `app.json` at root)
- The **binary tarball** `remmina.tar.bz2`

The portal signs the package with the community certificate and makes it available
for device installation.

---

## Installation on IGEL device

### Step 1 — Place the community certificate

The community package store certificate must be present **before** the device reboots
so that `igelpkgd` can verify and load the community package.

Copy `community.crt` (included in this repo) to the device:

```bash
mkdir -p /wfs/cmty/certs
cp community.crt /wfs/cmty/certs/
```

### Step 2 — Reboot the device

```bash
reboot
```

After reboot, `igelpkgd` loads the community certificate and the device is ready
to install community packages.

### Step 3 — Install the package

```bash
igelpkgctl install -f remmina-*.ipkg
```

Or install via IGEL UMS / App Portal.

---

## Project structure

```
.
├── app.json                    # App metadata (name, version, author)
├── community.crt               # Community package store certificate
├── igel/
│   ├── thirdparty.json         # Binary source URL + licenses
│   ├── install.json            # File selection rules
│   ├── dirs.json               # Persistent config directories
│   └── checksums.json          # Checksum verification
├── data/
│   ├── app.svg                 # App icon (colour)
│   ├── monochrome.svg          # App icon (monochrome)
│   ├── descriptions/en         # App description for portal
│   ├── changelogs/en           # Release notes
│   └── config/
│       ├── config.param        # IGEL session definition
│       ├── ui.json             # IGEL Setup UI structure
│       └── translation.json    # i18n strings
└── build/
    ├── Dockerfile              # Debian Bookworm build environment
    └── build.sh                # Orchestration script
```

---

## Updating versions

Edit `build/Dockerfile` to change component versions:

```dockerfile
ENV FREERDP_VERSION=3.24.0   # change to new tag
ENV REMMINA_VERSION=v1.4.43  # change to new tag
```

Update `app.json` accordingly:

```json
"version": "1.4.43+0.1.rc.1"
```

After rebuilding, update `igel/checksums.json` with the SHA256 of the new `remmina.tar.bz2`:

```bash
sha256sum remmina.tar.bz2
```

---

## Why Debian Bookworm as build base?

IGEL OS 12 is itself based on Debian Bookworm. The previous build used Ubuntu 22.04,
which caused library version mismatches at runtime (e.g. `libssl`, `libavahi`, `libfreerdp`).
Switching to Debian Bookworm as the build base ensures that compiled binaries link against
the same library versions available on the target device.

## Why FreeRDP 3.x?

IGEL OS ships FreeRDP 2.x which lacks:
- Correct NLA with modern CredSSP (Kerberos/NTLM)
- Smartcard passthrough (`/smartcard` redirector)
- Several security fixes for RDS environments

FreeRDP 3.x is compiled with:
- `WITH_PCSC=ON` — PC/SC smartcard support
- `WITH_KRB5=ON` — Kerberos authentication
- `WITH_GSSAPI=ON` — GSSAPI for NLA
- `WITH_FFMPEG=ON` — hardware-accelerated codec support
