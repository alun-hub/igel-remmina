# Remmina for IGEL OS 12

Remmina 1.4.43 + FreeRDP 3.x packaged as an IGEL OS 12 community app.
Supports RDP with NLA (Kerberos/NTLM via CredSSP) and smartcard passthrough via pcscd.

## Components

| Component       | Version          | Notes                                              |
|-----------------|------------------|----------------------------------------------------|
| Remmina         | 1.4.43           | Latest stable                                      |
| FreeRDP         | 3.24.0           | Required for NLA + smartcard (IGEL OS ships 2.x)   |
| Build base      | Debian Bookworm  | Must match IGEL OS to avoid library mismatches     |
| IGEL OS clean   | 12.7.4           | Strips files already present in IGEL OS            |
| Package size    | ~6 MB            |                                                    |

### Bundled libraries (not present in IGEL OS)

| Library               | Reason                                  |
|-----------------------|-----------------------------------------|
| libfreerdp3.so        | IGEL OS only ships FreeRDP 2            |
| libfreerdp-client3.so |                                         |
| libwinpr3.so          |                                         |
| libwinpr-tools3.so    |                                         |
| libuwac0.so           |                                         |
| libssh.so.4           | Not present in IGEL OS                  |
| libavahi-ui-gtk3.so   | Not present in IGEL OS                  |
| libavahi-client.so    |                                         |
| libavahi-common.so    |                                         |
| libavahi-glib.so      |                                         |
| libvncclient.so       | VNC support                             |
| libsodium.so          | Cryptography                            |

FFmpeg and ICU are **not** bundled — Bookworm versions match IGEL OS exactly.

---

## Step 1 — Build remmina.tar.bz2

### Prerequisites

- Podman or Docker installed and running
- Internet access (to clone FreeRDP and Remmina source)

### Run the build script

```bash
cd build
./build.sh 12.7.4    # argument = IGEL OS version for the clean list
```

This script:
1. Builds a Debian Bookworm container image
2. Compiles FreeRDP 3.x from source (with PCSC, KRB5, GSSAPI, FFMPEG)
3. Compiles Remmina from source against FreeRDP 3.x
4. Strips files already present in IGEL OS (using community clean lists)
5. Patches RPATH in all binaries with `patchelf`
6. Produces `remmina.tar.bz2` in the project root

> First build takes ~20–30 minutes. Subsequent builds reuse the container layer cache.

**Why Debian Bookworm?** IGEL OS 12 is based on Debian Bookworm. Building on Ubuntu 22.04
causes runtime crashes due to mismatched library versions (ICU 70 vs 72, FFmpeg .so.5 vs .so.6,
libssl, etc.). Bookworm eliminates all of these.

### RPATH patching

All binaries are patched with `patchelf` so they find their bundled libraries without
needing `LD_LIBRARY_PATH` in most cases:

| Binary / library                    | RPATH                              |
|-------------------------------------|------------------------------------|
| `usr/bin/remmina`                   | `$ORIGIN/../lib/x86_64-linux-gnu`  |
| `usr/lib/.../remmina/plugins/*.so`  | `$ORIGIN/../..`                    |
| FreeRDP 3 libs                      | `$ORIGIN`                          |

The session launch script still exports `LD_LIBRARY_PATH` as a fallback for avahi
and GTK dialogs.

---

## Step 2 — Package with IGEL App Creator Portal

The IGEL App Creator Portal at https://app.igel.com builds and signs the `.ipkg` file.

### Create a recipe zip

```bash
# Run from the project root
zip -r /tmp/remmina-recipe.zip app.json data/ igel/ input/
```

### Upload to the portal

1. Go to https://app.igel.com → **App Creator**
2. Create a new build, choose **Upload recipe (zip)**
3. Upload `remmina-recipe.zip` as the recipe
4. Upload `remmina.tar.bz2` as the thirdparty binary
5. Click **Build**
6. Download the signed `.ipkg` file

> **Why zip upload and not GitHub integration?**
> `igel/thirdparty.json` points to `file:///tmp/remmina.tar.bz2`. When using the GitHub
> integration the portal interprets this as "binary already on server" and skips the upload
> step — then fails because the file isn't actually there. To use GitHub integration instead,
> upload `remmina.tar.bz2` to a GitHub Release and update the URL in `thirdparty.json`.

---

## Step 3 — Install on the IGEL device

### Place the community certificate (first time only)

IGEL OS must trust the community certificate before it can install community packages.
Copy `community.crt` (included in this repo) to the device:

```bash
mkdir -p /wfs/cmty/certs/
cp community.crt /wfs/cmty/certs/
reboot    # igelpkgd loads the cert into the kernel keyring at boot
```

### Install the package

```bash
igelpkgctl install -f remmina-1.4.43+0.1.rc.1.ipkg
reboot    # required for the session script to activate
```

### Uninstall

```bash
igelpkgctl uninstall remmina
```

### Verify

```bash
# Session script must exist after reboot
ls -la /config/sessions/remmina0

# Check the RDP plugin loaded
ldd /services/remmina/usr/lib/x86_64-linux-gnu/remmina/plugins/remmina-plugin-rdp.so
```

Click the Remmina icon in the IGEL taskbar to launch.

---

## Project structure

```
.
├── app.json                       # App metadata (name, version, author)
├── community.crt                  # Community package store certificate
├── igel/
│   ├── thirdparty.json            # Binary source URL + licenses
│   ├── install.json               # File selection rules from tarball
│   ├── dirs.json                  # Persistent directories for user config
│   └── checksums.json             # Checksum verification
├── data/
│   ├── app.svg / monochrome.svg   # App icons
│   ├── descriptions/en            # App description for portal
│   ├── changelogs/en              # Release notes
│   └── config/
│       ├── config.param           # IGEL session definition
│       ├── ui.json                # IGEL Setup UI structure
│       └── translation.json       # i18n strings
├── input/
│   └── all/
│       ├── config/sessions/
│       │   └── remmina0           # Session launch script (placed on device at install)
│       └── usr/share/icons/...    # App icon for system icon theme
└── build/
    ├── Dockerfile                 # Debian Bookworm build environment
    └── build.sh                   # Orchestration script
```

---

## How the IGEL session system works

When the user clicks the Remmina icon in the IGEL taskbar, IGEL executes
`/config/sessions/remmina0`. This file is placed on the device from
`input/all/config/sessions/remmina0` during installation.

### Critical: node_action placement in config.param

`node_action=<wm_postsetup>` **must** be at the **top level of the `<sessions>` block**,
not inside the `<remmina%>` template:

```xml
<!-- CORRECT — node_action at top level -->
<sessions>
    <remmina%>
        extends_base=<sessions.base%>
    </remmina%>
    <remmina0>
        ...
    </remmina0>
    node_action=<wm_postsetup>    <!-- HERE, outside remmina% -->
</sessions>
```

```xml
<!-- WRONG — node_action inside template -->
<sessions>
    <remmina%>
        extends_base=<sessions.base%>
        node_action=<wm_postsetup>    <!-- causes session script to be deleted on reboot -->
    </remmina%>
    ...
</sessions>
```

**Why this matters:** When `node_action` is inside the template, IGEL's wm_postsetup
takes ownership of the `remmina0` session script — deleting it on every reboot and
attempting to regenerate it from `setup.ini`. Since `cmd` is never automatically
written to `setup.ini` for community apps (without UMS), the script is never
recreated and every launch fails with `/config/sessions/remmina0: not found`.

With `node_action` at the top level (matching the pattern used in the
[IGEL-OS-APP-RECIPES](https://github.com/IGEL-Community/IGEL-OS-APP-RECIPES) SuperTuxKart
example), the file from `input/all/config/sessions/remmina0` is left untouched and
persists across reboots.

---

## Updating versions

Edit `build/Dockerfile`:

```dockerfile
ENV FREERDP_VERSION=3.24.0   # new tag from github.com/FreeRDP/FreeRDP
ENV REMMINA_VERSION=v1.4.43  # new tag from gitlab.com/Remmina/Remmina
```

Edit `app.json`:

```json
"version": "1.4.43+0.1.rc.1"   # format: remmina_version+igel_build
```

Then rebuild from Step 1.

---

## Troubleshooting

**"libXxx: not found" on startup**
Add the missing library to the `copy_lib` section in `build/build-tar.sh` and rebuild.

**RDP plugin not shown in Remmina**
Check that the FreeRDP 3 libs are present and the plugin RPATH is correct:
```bash
ldd /services/remmina/usr/lib/x86_64-linux-gnu/remmina/plugins/remmina-plugin-rdp.so
```

**"/config/sessions/remmina0: not found" after reboot**
Verify that `node_action=<wm_postsetup>` is at the top level in `config.param` (see above).
Check that the file exists immediately after install (before rebooting).

**Signature verification failed on install**
```bash
ls /wfs/cmty/certs/community.crt   # must exist
# If missing: copy the cert and reboot
```

**Package size over 20 MB**
FFmpeg or ICU is being bundled. Make sure the build base is Debian Bookworm, not Ubuntu.
These libraries match IGEL OS and must not be bundled.
