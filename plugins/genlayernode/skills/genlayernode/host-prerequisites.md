# Prepare a clean validator host

Run this before downloading the node. Identify the OS with `/etc/os-release`;
the package commands below target **Ubuntu 24.04 AMD64**. For another distribution,
use its corresponding package names and Docker installation instructions. Do not
remove or replace an existing Docker installation during an ordinary node upgrade.

## Capacity and system packages

```bash
uname -sm
nproc
free -h
df -h /opt
sudo apt-get update
sudo apt-get install -y ca-certificates curl wget gnupg git jq tar gzip unzip \
  python3 python3-pip python3-venv python3-yaml libstdc++6
python3 -c 'import sys, yaml; assert sys.version_info >= (3, 10)'
python3 -m pip --version
python3 -m venv --help >/dev/null
```

Require Linux x86_64, 8 cores, 16 GB RAM and 128 GB SSD/NVMe capacity, with enough
free space for the extracted release, GenVM runners, database and backups. Python
3.10+ is required by the current setup script. `libstdc++6` is needed by the LIEF
wheel used during ELF setup. The release setup creates its own Python environment
and installs its pinned dependencies; do not replace that with system-wide pip.

## Docker Engine and Compose

Both deployment modes use WebDriver in Docker. Install Engine and the Compose
plugin from [Docker's official Ubuntu repository](https://docs.docker.com/engine/install/ubuntu/).
For a **fresh Ubuntu host** with no conflicting Docker/containerd packages:

```bash
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
. /etc/os-release
printf '%s\n' "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME:-$VERSION_CODENAME} stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo docker version
sudo docker compose version
sudo docker run --rm hello-world
```

Use Compose **2.24+**: the release uses `env_file.required`, unsupported by older
versions. Run Docker administration as an authorized host administrator. Do not
add the node's service user to the Docker group; WebDriver metrics use the shipped
read-only socket proxy. If using sudo, use it consistently for Compose commands.

## Node.js and staking CLI

The owner machine needs Node.js **20+** (the v0.40 CLI's Commander dependency
requires it); use a supported Node.js **22** installation for this procedure.
The machine executing `scripts/check-network.mjs` also needs Node.js. On a clean
Ubuntu machine, install Node 22 using your approved package source; the NodeSource
repository bootstrap is one option:

```bash
curl -fsSL https://deb.nodesource.com/setup_22.x -o /tmp/nodesource-setup.sh
# Inspect the downloaded repository setup script before executing it.
sudo -E bash /tmp/nodesource-setup.sh
sudo apt-get install -y nodejs
node -e 'if (Number(process.versions.node.split(".")[0]) < 20) process.exit(1)'
npm --version
```

On Linux the CLI's optional OS-keychain integration uses `libsecret`. If installing
or building the CLI on this host, install its native build dependencies first:

```bash
sudo apt-get install -y build-essential pkg-config libsecret-1-dev
: "${CLI_VERSION:?Set the exact qualified Bradbury Phase 2 CLI version}"
npm install -g "genlayer@${CLI_VERSION}"
genlayer --version
```

Use a user-owned npm prefix or your approved global installation permissions. A
headless host need not have an unlocked desktop keychain: use the CLI's encrypted
keystore/password flow. Keep the owner's signing account on the owner machine.

## Release verification tools

`curl`, `tar` and `sha256sum` are required. Install `cosign` from your approved
package source following [Sigstore's installation guide](https://docs.sigstore.dev/cosign/system_config/installation/),
then check `cosign version`. Record the installed version. Stop if it is absent;
do not skip signature verification or treat an unverified download as a release.

Before proceeding, check tool presence and Docker daemon access:

```bash
for tool in curl tar sha256sum cosign node python3; do
  command -v "$tool" || exit 1
done
sudo docker info >/dev/null
sudo docker compose version
```

A container-based package/setup test validates userspace dependencies, but does
not validate systemd, Docker daemon installation or the server's firewall. Report
those checks separately when qualifying a fresh server.
