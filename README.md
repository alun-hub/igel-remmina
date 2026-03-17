# Remmina for IGEL OS 12

Remmina remote desktop client built with FreeRDP 3.x for IGEL OS 12.  
Includes full NLA authentication (Kerberos/NTLM via CredSSP) and smartcard passthrough support.

| Component | Version |
|---|---|
| Remmina | 1.4.38 |
| FreeRDP | 3.10.3 |
| Build base | Ubuntu 22.04 (glibc 2.35) |
| Target | IGEL OS 12.7.x |

---

## Prerequisites

- **Podman** (or Docker) installed and running
- **IGEL OS App SDK** container image loaded:
  ```bash
  podman load -i igelpkg.tar
  # Verify: podman images | grep igelpkg
  ```
- `wget`, `patchelf` available on the build host
- Internet access to clone FreeRDP and Remmina from source

---

## Step 1 — Build `remmina.tar.bz2`

This step compiles FreeRDP 3.x and Remmina from source inside a container and produces a binary tarball.

```bash
cd build/
chmod +x build.sh
./build.sh 12.7.4
```

Replace `12.7.4` with your target IGEL OS version (used to strip libraries already present in IGEL OS).

The script will:
1. Build a Ubuntu 22.04 container image with all build dependencies
2. Download IGEL OS clean-lists from [IGEL-Community/IGEL-Custom-Partitions](https://github.com/IGEL-Community/IGEL-Custom-Partitions) to strip already-shipped libraries
3. Compile FreeRDP 3.10.3 with PCSC, Kerberos, GSSAPI, ALSA, PulseAudio, CUPS, FFmpeg
4. Compile Remmina 1.4.38 against the built FreeRDP
5. Patch RPATH so Remmina finds libs at `/services/remmina/usr/lib/x86_64-linux-gnu`
6. Output: **`remmina.tar.bz2`** in the project root

> **Note:** The build takes ~20–30 minutes on first run (clones and compiles from source).

---

## Step 2 — Update `thirdparty.json` with the binary URL

Before building the IGEL package, `igel/thirdparty.json` must point to a **publicly accessible URL** where `remmina.tar.bz2` is hosted (e.g. a GitHub Release asset).

1. Upload `remmina.tar.bz2` to a public location (GitHub Releases, etc.)
2. Edit `igel/thirdparty.json` and replace the `url` value:

```json
[
  {
    "url": "https://your-host/path/to/remmina.tar.bz2",
    "licenses": [
      {
        "name": "GPL-2.0-only",
        "text": "GNU General Public License v2.0 only"
      },
      {
        "name": "Apache-2.0",
        "text": "Apache License 2.0"
      }
    ]
  }
]
```

> For **local builds only** you can keep `file:///tmp/remmina.tar.bz2` and copy the tarball to `/tmp/` before running igelpkg.

---

## Step 3 — Build the IGEL `.ipkg` (local / dev)

This step requires the IGEL OS App SDK container (`igelpkg`).

```bash
# Copy tarball to /tmp (if using local file:// URL)
cp remmina.tar.bz2 /tmp/remmina.tar.bz2

# Build the package
podman run --rm \
  -v /tmp/remmina.tar.bz2:/tmp/remmina.tar.bz2:ro,z \
  -v "$(pwd)":/app:z \
  --entrypoint /bin/bash \
  localhost/igelpkg:latest \
  -c 'cd /app && igelpkg build -a x64'
```

Output: `igelpkg.output/remmina-1.4.38+0.1.rc.1.ipkg`

**Debug mode** (keeps temp files and writes log):
```bash
igelpkg build -a x64 -kl
# Temp files: igelpkg.out/ and igelpkg.tmp/
# Log file:   igelpkg.log
```

---

## Step 4 — Sign and publish via IGEL App Creator Portal

For community distribution, signing is handled server-side by IGEL.

1. Zip the recipe with `app.json` at the root:
   ```bash
   cd /path/to/igel-remmina
   zip -r remmina-recipe.zip . \
     --exclude "./build/*" \
     --exclude "./igelpkg.output/*" \
     --exclude "./igelpkg.tmp/*" \
     --exclude "./igelpkg.out/*" \
     --exclude "./igelpkg.log" \
     --exclude "./*.tar.bz2"
   ```
2. Make sure `igel/thirdparty.json` points to a public URL for `remmina.tar.bz2` (Step 2)
3. Upload `remmina-recipe.zip` to the **IGEL App Creator Portal**
4. The portal downloads the binary, builds, and signs the package with the community certificate
5. Download the signed `.ipkg` from the portal

---

## Step 5 — Install on an IGEL OS device

```bash
# On the IGEL device, logged in as root:
igelpkgctl install -f /path/to/remmina-1.4.38+0.1.rc.1.ipkg
```

Or deploy via IGEL UMS (Universal Management Suite) App Portal.

---

## Project structure

```
.
├── app.json                          # App metadata (name, version, author)
├── igel/
│   ├── thirdparty.json               # Binary source URL + licenses
│   ├── install.json                  # File selection rules
│   ├── dirs.json                     # Persistent config directories
│   └── checksums.json                # Checksum verification
├── data/
│   ├── app.svg                       # App icon (colour)
│   ├── monochrome.svg                # App icon (monochrome)
│   ├── descriptions/en               # App description for portal
│   ├── changelogs/en                 # Release notes
│   └── config/
│       ├── config.param              # IGEL session definition
│       ├── ui.json                   # IGEL Setup UI structure
│       └── translation.json          # i18n strings
├── input/
│   └── all/
│       ├── config/sessions/remmina0  # Session launcher script
│       └── usr/share/icons/...       # Desktop icon
└── build/
    ├── Dockerfile                    # Ubuntu 22.04 build environment
    └── build.sh                      # Orchestration script
```

---

## Runtime behaviour

When installed, Remmina is mounted at `/services/remmina/`. The session launcher at  
`/services/remmina/.scripts/sessions/remmina0` sets:

```bash
export LD_LIBRARY_PATH=/services/remmina/usr/lib/x86_64-linux-gnu
export GDK_BACKEND=x11
exec /services/remmina/usr/bin/remmina
```

User configuration is stored persistently at:
- `/userhome/.config/remmina/`
- `/userhome/.local/share/remmina/`

---

## Why Ubuntu 22.04 as build base?

IGEL OS 12 is based on Debian Bookworm (glibc 2.36). Binaries compiled on Ubuntu 24.04 (glibc 2.39) will **not** run on IGEL OS — they require a newer glibc than what is available. Ubuntu 22.04 (glibc 2.35) produces binaries compatible with glibc 2.36.
