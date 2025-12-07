# Summary of what this repository builds

This repo provisions and configures a cross-platform Minecraft server hosted on an Azure Linux VM, using Terraform and Cloudflare for a friendly domain name. The server is designed to support:

* Bedrock clients (Xbox, PlayStation 5, Windows Bedrock)
* Java clients (Windows/Mac Java)

Cross-play is enabled by running a Paper (Java) server with Geyser + Floodgate so Bedrock players can join the Java world. The architecture is built for clean DEV/PROD parity using thin environment wrappers that call a single component module. The VM uses cloud-init to place a canonical bootstrap script and a systemd unit file, then runs the bootstrap to prepare OS packages, the minecraft service account, Java, and persistent world storage on a managed data disk with bind mounts.

The server runtime composition is driven by a `server/manifest.toml` and a Python `apply.py` script (you will write) that installs/updates Paper, Geyser, Floodgate, and config files in an idempotent manner. The repo also includes a Terraform-backend bootstrap shell script that creates the Azure Storage backend resources via AZ CLI so state setup is repeatable and not manual.

This is an open-source, portfolio-grade structure that avoids Terraform workspaces, avoids monolithic files, keeps secrets out of Git, and keeps environment folders thin.

---

## Target directory structure (canonical)

```plaintext
.
├── infra
│   ├── terraform
│   │   ├── environments
│   │   │   ├── dev
│   │   │   │   ├── backend.tf
│   │   │   │   ├── main.tf
│   │   │   │   ├── secrets.auto.tfvars
│   │   │   │   ├── secrets.auto.tfvars.example
│   │   │   │   └── terraform.tfvars
│   │   │   └── prod
│   │   │       ├── backend.tf
│   │   │       ├── main.tf
│   │   │       ├── secrets.auto.tfvars
│   │   │       ├── secrets.auto.tfvars.example
│   │   │       └── terraform.tfvars
│   │   ├── modules
│   │   │   └── minecraft_vm
│   │   │       ├── cloudinit.tf
│   │   │       ├── disk.tf
│   │   │       ├── dns.tf
│   │   │       ├── network.tf
│   │   │       ├── nsg.tf
│   │   │       ├── outputs.tf
│   │   │       ├── README.md
│   │   │       ├── templates
│   │   │       │   ├── bootstrap.sh
│   │   │       │   ├── cloud-init.yaml.tftpl
│   │   │       │   └── minecraft.service
│   │   │       ├── variables.tf
│   │   │       └── vm.tf
│   │   └── README.md
│   └── terraform-bootstrap
│       ├── bootstrap-backend.sh
│       └── README.md
├── server
│   ├── apply.py
│   ├── manifest.toml
│   ├── README.md
│   └── config
│       ├── paper
│       ├── geyser
│       └── floodgate
├── README.md
├── LICENSE
└── pyproject.toml
```

---

## Guiding rules (do not deviate)

1. **Environment folders must be thin wrappers.**

   * They should only configure provider/backend and call the module.

2. **The module is the single source of truth for architecture.**

   * Add resources only inside `modules/minecraft_vm`.

3. **Templates live with the module that injects them.**

   * Canonical bootstrap and unit files live under `templates/`.

4. **Commit safe defaults, not secrets.**

   * Commit `terraform.tfvars`.
   * Never commit `secrets.auto.tfvars`.

5. **Cloud-init writes files and runs bootstrap on first boot.**

   * Bootstrap prepares the OS and persistent world storage.

6. **`apply.py` is the idempotent runtime installer/updater.**

   * It reads `manifest.toml` to install Paper/Geyser/Floodgate and copy configs.

---

## Step-by-step build guide

### Phase 0 — Repo foundation

1. Create the repo with:

   * root `README.md`
   * `LICENSE`
   * `pyproject.toml` (for the Python tooling in `server/`)
   * `server/README.md`
   * `infra/terraform/README.md`
   * `infra/terraform-bootstrap/README.md`

2. Add `.gitignore` entries:

   * ignore any secret tfvars:

     * `**/secrets.auto.tfvars`
   * ignore Python venvs/caches normally used in your setup

3. Documentation checkpoint:

   * In root `README.md`, add a short “Architecture Overview” section stating:

     * Azure Linux VM
     * Managed data disk for persistent world
     * Paper + Geyser + Floodgate
     * Terraform dev/prod thin wrappers
     * Cloudflare DNS
     * `apply.py` + `manifest.toml` runtime model

---

### Phase 1 — Terraform backend bootstrap

Goal: eliminate manual state infrastructure setup.

1. Create:

   * `infra/terraform-bootstrap/bootstrap-backend.sh`
   * `infra/terraform-bootstrap/README.md`

2. The shell script must be idempotent and do the following:

   * Ensure Azure CLI login state is valid.
   * Create (if missing):

     * resource group
     * storage account
     * blob container for Terraform state
   * Output (echo) the final names used.

3. Decide a strict naming scheme:

   * pick one base prefix used for both dev/prod backend resources
   * if you separate state per env, reflect that in container names, not storage accounts

4. Documentation checkpoint:

   * In `infra/terraform-bootstrap/README.md`, include:

     * required env vars (if any)
     * default naming behavior
     * the exact “run this before terraform init” instruction

---

### Phase 2 — Terraform module implementation (`minecraft_vm`)

Goal: component module that represents a full Minecraft server instance.

#### 2.1 Variables contract

1. In `variables.tf`, define only the inputs you expect users to override:

   * `location`
   * `resource_group_name`
   * `env_name` (e.g., `dev`, `prod`)
   * `name_prefix`
   * `vm_size`
   * `admin_username`
   * `ssh_public_key`
   * `java_port` (default 25565)
   * `bedrock_port` (default 19132)
   * `data_disk_size_gb`
   * `cloudflare_zone_id` and record details if DNS is in-module
   * any tags structure you standardize on

2. Use defaults for safe, portable values.

3. Keep locals small:

   * derived names and tags only

#### 2.2 Network

1. In `network.tf`, define:

   * VNET
   * subnet
   * NIC
   * Public IP (if not separated)

2. Ensure naming includes `env_name` to avoid collisions.

#### 2.3 NSG

1. In `nsg.tf`, define:

   * NSG
   * inbound rules for:

     * Java port
     * Bedrock port
     * SSH (locked down if you want to be strict)

2. Associate the NSG to the NIC or subnet.

#### 2.4 Disk

1. In `disk.tf`, define:

   * managed data disk
   * attachment to the VM

2. Set the disk to map to the expected LUN you reference in bootstrap.

#### 2.5 VM

1. In `vm.tf`, define:

   * Linux VM resource
   * admin username + SSH key auth only
   * `custom_data = local.custom_data_b64`

2. Ensure the base image is a modern Ubuntu LTS.

#### 2.6 DNS (Cloudflare)

1. In `dns.tf`, define:

   * A record pointing to the VM public IP
   * any SRV record if you want quality-of-life for Java clients

2. If you choose to keep DNS out of the module later, remove this file.

   * For now, keep it if it simplifies your single-module story.

#### 2.7 Outputs

1. In `outputs.tf`, expose:

   * public IP
   * FQDN
   * resource IDs that might be useful for troubleshooting

#### 2.8 Module README

1. In `modules/minecraft_vm/README.md`, describe:

   * what the module creates
   * required inputs
   * what cloud-init + bootstrap do
   * expected disk mount path and why

2. Documentation checkpoint:

   * add a short “Conventions” section that states:

     * env roots must not define resources
     * module is the single source of truth

---

### Phase 3 — Cloud-init + bootstrap + service templates

Goal: deterministic first-boot configuration.

#### 3.1 `templates/bootstrap.sh`

1. This must be the canonical bootstrap script.

2. It must:

   * require root
   * install OS deps
   * install Java 21
   * install Python runtime for `apply.py`
   * create `minecraft` system group/user
   * create required directories
   * format the data disk only if needed
   * mount disk to `/mnt/mcdata`
   * create world directory on disk
   * bind mount to `/opt/minecraft/world`
   * update `/etc/fstab` idempotently
   * copy/install the systemd unit if your flow needs it, or assume cloud-init already wrote it
   * `systemctl daemon-reload`
   * `systemctl enable minecraft`

3. The script must assume the stable Azure disk path:

   * `/dev/disk/azure/scsi1/lun0`

4. Keep this script free of secrets.

#### 3.2 `templates/minecraft.service`

1. This is the canonical unit file name.

2. The unit must:

   * run as `minecraft:minecraft`
   * set working directory to `/opt/minecraft/server`
   * start Paper with JVM flags appropriate for your memory defaults
   * send logs to journald and/or your `/var/log/minecraft` path if wired

3. Keep it as a concrete unit file.

   * No `.template` suffix unless you later truly parameterize it.

#### 3.3 `templates/cloud-init.yaml.tftpl`

1. The cloud-init template must:

   * `write_files` for:

     * `/opt/minecraft/bootstrap.sh` (mode 0755)
     * `/opt/minecraft/minecraft.service` (mode 0644)
   * `runcmd`:

     * `bash /opt/minecraft/bootstrap.sh`

2. The template should accept only the minimal values needed:

   * ports if referenced
   * environment name if embedded in messages

#### 3.4 `cloudinit.tf`

1. `cloudinit.tf` should:

   * read the two template files:

     * `bootstrap.sh`
     * `minecraft.service`
   * render `cloud-init.yaml.tftpl` with `templatefile`
   * base64 encode the result into:

     * `local.custom_data_b64`

2. This file should not define resources.

3. Documentation checkpoint:

   * add a short explanation in `infra/terraform/README.md`

     * cloud-init installs bootstrap + service
     * bootstrap prepares disk + user + Java
     * `apply.py` handles runtime install/update

---

### Phase 4 — Environment wrappers (DEV + PROD)

Goal: two thin roots calling the same module.

For each of:

* `infra/terraform/environments/dev`
* `infra/terraform/environments/prod`

1. `backend.tf` should:

   * reference the storage account/container created by your bootstrap script
   * keep state isolated per env

2. `main.tf` should:

   * configure provider
   * instantiate the module once
   * pass in:

     * env_name
     * naming prefix
     * input values sourced from variables/tfvars

3. `terraform.tfvars` should contain safe defaults:

   * VM size differences if any
   * disk size
   * naming
   * ports

4. `secrets.auto.tfvars.example` should list placeholders for:

   * Cloudflare token or zone IDs if you keep those as variables
   * any other sensitive config

5. Local-only usage:

   * `secrets.auto.tfvars` exists but is ignored by Git

6. Documentation checkpoint:

   * in `infra/terraform/README.md`, document the exact commands:

     * run backend bootstrap script
     * `cd environments/dev`
     * `terraform init`
     * `terraform plan`
     * `terraform apply`

---

### Phase 5 — Server runtime layer

Goal: idempotent install/update logic separate from infrastructure.

#### 5.1 `server/manifest.toml`

1. This file is your declarative runtime contract.

2. Keep it minimal and explicit:

   * Paper version
   * Geyser version
   * Floodgate version
   * ports (if you want runtime awareness)
   * any file layout assumptions

3. Ensure the naming convention is clear:

   * a single top-level table is fine
   * avoid redundant wrapper tables

#### 5.2 `server/config/*`

1. These directories hold:

   * canonical configs for Paper/Geyser/Floodgate
2. Your `apply.py` should copy these into:

   * `/opt/minecraft/config/...`
   * and/or plugin config locations as required

#### 5.3 `server/apply.py`

You will write this.

It must:

1. Parse `manifest.toml`.
2. Validate versions are present and sane.
3. Ensure directory structure exists under `/opt/minecraft`:

   * `server`
   * `plugins`
   * `config`
   * `world` (already mounted)
4. Download Paper to:

   * `/opt/minecraft/server/paper.jar`
5. Download plugin jars:

   * Geyser
   * Floodgate
     into `/opt/minecraft/plugins`
6. Copy repo config directories into correct on-VM locations.
7. Be idempotent:

   * compare current installed versions or file hashes
   * only replace when versions differ
8. Optionally restart the service safely:

   * stop → update → start
   * but default to not restarting unless a change occurred

#### 5.4 `server/README.md`

Document:

* what `apply.py` does
* how to run it on the VM
* how to update versions in `manifest.toml`
* what to expect for Bedrock vs Java features

---

### Phase 6 — End-to-end execution flow

This is the exact order a new contributor should follow.

1. **Bootstrap Terraform backend**

   * `cd infra/terraform-bootstrap`
   * run `bootstrap-backend.sh`

2. **Provision DEV**

   * `cd infra/terraform/environments/dev`
   * create `secrets.auto.tfvars` from the example if needed
   * `terraform init`
   * `terraform plan`
   * `terraform apply`

3. **Validate first boot**

   * SSH into DEV VM
   * confirm:

     * `minecraft` user exists
     * disk is mounted to `/mnt/mcdata`
     * bind mount exists at `/opt/minecraft/world`
     * `systemctl status minecraft` shows enabled

4. **Run runtime installer**

   * copy or pull repo to VM if your workflow requires it
   * run `python3 /path/to/server/apply.py`

     * targeting the manifest in the repo

5. **Connect and test**

   * Java client test
   * Bedrock client test via Geyser

6. **Provision PROD**

   * repeat the exact same steps under `environments/prod`

7. **Promote changes**

   * changes to server runtime:

     * update `manifest.toml` + configs
     * run `apply.py` in DEV
     * then run the same in PROD
   * changes to infrastructure:

     * update module once
     * both envs inherit

---

## Notes on cross-platform expectations

1. Bedrock via Geyser is excellent but not perfect.
2. Some feature mismatches are expected.
3. This is normal and should be documented succinctly in `server/README.md`
   so PS5 players know why occasional differences exist.

---

## Minimal “portfolio polish” additions

1. Root `README.md`

   * architecture diagram (optional)
   * quickstart section

2. `infra/terraform/README.md`

   * module vs env responsibilities

3. `CONTRIBUTING.md`

   * how to add new resources (module-only rule)
   * secrets handling

---

## Final sanity constraints

* Do not add real resources in `environments/*`.
* Do not commit `secrets.auto.tfvars`.
* Do not duplicate bootstrap or service files outside module templates.
* Keep cloud-init free of secrets.
* Keep `apply.py` idempotent and version-driven.

