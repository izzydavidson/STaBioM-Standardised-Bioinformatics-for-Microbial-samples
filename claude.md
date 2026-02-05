# Task: Enable FAST5 → POD5 → Dorado support in STaBioM LR pipelines

You are working inside the STaBioM repository.

GO STRAIGHT TO IMPLEMENTATION.
DO NOT ENTER PLANNING MODE.
DO NOT COMMIT CHANGES.
OUTPUT ALL MODIFIED FILES IN FULL.
DO NOT CHANGE ANY LOGIC UNRELATED TO POD5 / DORADO.
DO NOT UPGRADE VERSIONS UNLESS EXPLICITLY REQUESTED.

---

## Part 1 — Docker images (CRITICAL)

Problem:
Long-read pipelines (lr_amp, lr_meta) fail when FAST5 input is provided because the Docker images do not contain the POD5 tooling required to convert FAST5 → POD5 before Dorado basecalling.

Goal:
All long-read Docker images must support FAST5 input out of the box.

### Required changes

For **ALL long-read Dockerfiles** (e.g. dockerfile.lr and any shared LR base images):

1. Install the Oxford Nanopore POD5 tools inside the container so that the following command exists and works:
   - `pod5 convert fast5`

2. Ensure the `pod5` binary is available on PATH at runtime.

3. Do NOT:
   - Change existing pipeline logic
   - Remove FASTQ support
   - Alter Kraken, Emu, Valencia, or host-depletion logic

### Implementation constraints

- Use the official POD5 tooling (pip install is acceptable)
- Keep installation minimal (no dev extras)
- Ensure compatibility with Ubuntu 22.04
- Do not pin unnecessary versions

---

## Part 2 — Dorado availability in containers

Problem:
Dorado is expected to run inside LR containers when FAST5 or POD5 input is provided, but model availability is not guaranteed.

Goal:
Ensure Dorado can run fully inside Docker with downloadable models.

### Required changes

1. Ensure `dorado` is installed and available in LR Docker images.
2. Ensure Dorado model paths are consistent with existing STaBioM expectations.
3. Do not hardcode model downloads into the Dockerfile.

---

## Part 3 — Setup wizard: Dorado model download support

Problem:
The STaBioM setup wizard currently downloads databases (Emu, human reference, Valencia centroids) but does not handle Dorado models.

Goal:
Allow Dorado models to be downloaded during `stabiom setup`, alongside Valencia tools.

### Required functionality

1. Add Dorado model support to the setup wizard so users can download models interactively or automatically.
2. Include the following model as a selectable and default-supported option:
   - `dna_r10.4.1_e8.2_400bps_hac@v4.1.0`
3. Downloaded models must be stored in the STaBioM internal tools/models location (consistent with other tools).
4. The pipeline must auto-detect downloaded Dorado models without requiring extra flags.

### Constraints

- Do not break existing setup flows
- Do not remove Valencia setup
- Do not require users to manually install Dorado models
- Do not introduce new CLI commands

---

## Validation requirements

After implementation, the following must work:

- `stabiom run -p lr_meta -i *.fast5 ...` inside Docker
- FAST5 → POD5 conversion occurs successfully
- Dorado basecalling runs using downloaded models
- No "Missing command" errors
- FASTQ-based workflows remain unchanged
- Valencia functionality remains unchanged

---

## Output requirements

- Output all modified Dockerfiles in full
- Output all modified setup / wizard files in full
- Do not include explanations unless necessary
- Do not commit changes
