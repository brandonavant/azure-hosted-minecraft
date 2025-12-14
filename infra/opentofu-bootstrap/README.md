# OpenTofu Backend Bootstrap

This directory contains a small, idempotent bootstrap script that provisions the **OpenTofu remote state backend** for this project using the Azure CLI.

The resources created here are **only** for OpenTofu state and are separate from the resource groups that will hold the actual Minecraft infrastructure.

This is a one-time bootstrap you run manually from an admin's machine; not something to wire into CI/CD. It depends on an interactive Azure login and elevated privileges, and you typically need to do it only once to create the shared remote state backend before any pipelines run.

---

## What this script does

`bootstrap-backend.sh`:

1. Ensures you are logged in to Azure and using the correct subscription.
2. Creates (if missing) a **resource group** dedicated to OpenTofu state.
3. Creates (if missing) a **storage account** in that resource group.
4. Creates (if missing) two **blob containers** inside that account:

   * `tfstate-dev` (for the dev environment)
   * `tfstate-prod` (for the prod environment)
5. Prints a summary of the final names to use in your OpenTofu `backend` configuration.

The script is **idempotent**: if anything already exists, it reuses it and does not delete or modify it.

---

## Prerequisites

You need:

* Azure CLI (`az`) installed and available on your PATH.
* An Azure account with permissions to:

  * Create **resource groups**.
  * Create **storage accounts**.
  * Manage **blob containers** in that storage account (via Azure AD; the script uses `--auth-mode login`).

You must be able to log in interactively with `az login` or already be logged in with appropriate credentials.

---

## Configuration (environment variables)

The script is configured entirely via environment variables. If you want to keep them in a file, copy `.env.example` to `.env`, fill in the real values there (leave `.env.example` unchanged), and `source .env` before running the script:

* `TF_BACKEND_SUBSCRIPTION_ID`
  The subscription ID where the backend resources will be created.

* `TF_BACKEND_LOCATION`
  Azure region for the backend resources (e.g., `eastus`, `centralus`).

* `TF_BACKEND_PROJECT_NAME`
  Short project name used as part of the naming convention (e.g., `mcserver`).

* `TF_BACKEND_TEAM_NAME`
  Short team or owner name used as part of the naming convention (e.g., `plat`).

All four variables are **required**. If any are missing or empty, the script exits with an error.

---

## Naming conventions

Given:

* `TF_BACKEND_TEAM_NAME = <team>`
* `TF_BACKEND_PROJECT_NAME = <project>`

the script derives:

### Resource group

```text
rg-<team>-<project>-tfstate
```

Example:

```text
rg-plat-mcserver-tfstate
```

This resource group is **only** for OpenTofu state.

### Storage account

```text
st<team><project>tfstate
```

Then normalized to meet Azure storage account rules:

* All **lowercase**.
* Non-alphanumeric characters are **removed**.
* Length must be between **3 and 24** characters.

If normalization produces a name shorter than 3 or longer than 24 characters, the script exits with an error and prints a message. Choose team/project names that keep the resulting storage account name within this limit.

> Note: Storage account names are **globally unique** across Azure. If the normalized name is already in use in another subscription or tenant, the `az storage account create` call will fail and the script will exit.

### Blob containers

Two containers are created in the storage account:

* `tfstate-dev`
* `tfstate-prod`

These are used as the `container_name` values in the OpenTofu backend configuration for the dev and prod environments, respectively.

---

## What the script does, step by step

At a high level, `bootstrap-backend.sh`:

1. Validates that all required environment variables are set.
2. Verifies that the Azure CLI is installed.
3. Verifies that you are logged in to Azure (`az account show`), and if not, prompts you to log in via `az login`.
4. Sets the active subscription to `TF_BACKEND_SUBSCRIPTION_ID`.
5. Ensures the resource group `rg-<team>-<project>-tfstate` exists in `TF_BACKEND_LOCATION`.
6. Ensures the storage account `st<team><project>tfstate` (normalized) exists in that resource group.
7. Ensures blob containers `tfstate-dev` and `tfstate-prod` exist in that storage account, with:

   * `--public-access off`
   * `--auth-mode login`
8. Prints a final summary of:

   * Resource group name
   * Storage account name
   * Container names
   * Subscription ID
   * Location

The script never deletes existing resources or state.

---

## How to run

From this directory (`infra/opentofu-bootstrap`):

### Option 1: Using a `.env` file (recommended)

1. Copy `.env.example` to `.env` and fill in the actual values:

   ```bash
   cp .env.example .env
   # Edit .env with your real values (do not edit .env.example)
   ```

2. Source the file and run the script:

   ```bash
   source .env && ./bootstrap-backend.sh
   ```

### Option 2: Exporting variables directly

1. Set the required environment variables in your shell. For example:

   ```bash
   export TF_BACKEND_SUBSCRIPTION_ID="<your-subscription-id>"
   export TF_BACKEND_LOCATION="eastus"
   export TF_BACKEND_PROJECT_NAME="mcserver"
   export TF_BACKEND_TEAM_NAME="plat"
   ```

2. Run the script:

   ```bash
   ./bootstrap-backend.sh
   ```

3. If everything succeeds, you’ll see a summary like:

   ```text
   OpenTofu backend bootstrap completed successfully.
   Resource Group: rg-plat-mcserver-tfstate
   Storage Account: stplatmcservertfstate
   Blob Containers: tfstate-dev, tfstate-prod
   Subscription ID: <your-subscription-id>
   Location: eastus
   ```

You can safely run this script multiple times. If resources already exist, it will simply report that and skip creation.

---

## Using the backend in OpenTofu environments

The OpenTofu environment folders (`infra/opentofu/environments/dev` and `infra/opentofu/environments/prod`) will use the backend resources created here.

The mapping is:

* **Dev environment backend (`environments/dev/opentofu.tf`):**

  * `resource_group_name = rg-<team>-<project>-tfstate`
  * `storage_account_name = st<team><project>tfstate` (normalized name)
  * `container_name = tfstate-dev`
  * `key =` some dev-specific state file name (e.g., `dev.tfstate`)

* **Prod environment backend (`environments/prod/opentofu.tf`):**

  * `resource_group_name = rg-<team>-<project>-tfstate`
  * `storage_account_name = st<team><project>tfstate` (same as dev)
  * `container_name = tfstate-prod`
  * `key =` some prod-specific state file name (e.g., `prod.tfstate`)

Both environments share:

* The **same** resource group.
* The **same** storage account.
* **Different** containers and keys per environment.

> Important: The resource group created by this script is for the **OpenTofu backend only**. The actual Minecraft infrastructure will live in separate resource groups created and managed by OpenTofu modules.

---

## Troubleshooting

Common issues:

### 1. Missing or empty environment variables

**Symptom:**

* The script exits with a message like:

* `ERROR: Environment variable TF_BACKEND_PROJECT_NAME is not set.`

**Fix:**

* Ensure all of the following are set before running:

  * `TF_BACKEND_SUBSCRIPTION_ID`
  * `TF_BACKEND_LOCATION`
  * `TF_BACKEND_PROJECT_NAME`
  * `TF_BACKEND_TEAM_NAME`

---

### 2. Azure CLI not installed

**Symptom:**

* The script prints:

  * `ERROR: Azure CLI (az) is not installed. Please install it and try again.`

**Fix:**

* Install the Azure CLI following Microsoft’s instructions, then re-run the script.

---

### 3. Not logged in or wrong subscription

**Symptom:**

* `az account show` fails, or `az account set` fails for the given subscription ID.

**Fix:**

* Run `az login` and ensure:

* The subscription ID in `TF_BACKEND_SUBSCRIPTION_ID` is valid.
  * Your account has access to that subscription.

---

### 4. Storage account name invalid or already taken

**Symptoms:**

* Script exits with:

  * `ERROR: Storage account name '...' is invalid after normalization...`
* Or Azure returns an error that the name is already in use.

**Fix:**

* Adjust `TF_BACKEND_TEAM_NAME` and/or `TF_BACKEND_PROJECT_NAME` so that:

  * After removing non-alphanumeric characters and lowercasing, the combined storage account name:

    * Is between 3 and 24 characters.
    * Is not already in use by another Azure tenant.

---

### 5. Permissions errors for container operations

**Symptom:**

* Errors related to `az storage container show` or `az storage container create` with `--auth-mode login`.

**Fix:**

* Ensure your logged-in identity has the necessary RBAC role on the storage account or subscription:

  * e.g., **Storage Blob Data Contributor** or equivalent.

---

## Safety and idempotency

* The script is designed to be **safe to rerun**:

  * Existing resource groups, storage accounts, and containers are reused.
* It **does not**:

  * Delete resource groups.
  * Delete storage accounts.
  * Delete or modify existing OpenTofu state blobs.

If you need to change the naming scheme or move state between accounts/containers, handle that carefully at the OpenTofu level.

---

## Next steps

After running this script successfully:

1. Go to infra/opentofu/environments/dev and infra/opentofu/environments/prod.

2. Configure backend.tf in each environment to use:
   * The resource group name and storage account name printed by this script.
   * The appropriate container:

     * `tfstate-dev` for dev.
     * `tfstate-prod` for prod.
3. Run `tofu init` in each environment directory to wire OpenTofu to the remote backend.
