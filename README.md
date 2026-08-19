# Run oobabooga textgen on RunPod

[![Docker Image Version](https://img.shields.io/docker/v/ls250824/run-textgen)](https://hub.docker.com/r/ls250824/run-textgen)

## This pod downloads models as specified in the **environment variables**

- Models are automatically downloaded based on the specified paths in the environment configuration.
- textgen starts first without automatically loading a model; provisioning runs afterwards, and downloaded models can then be loaded from the textgen interface.
- Authentication credentials can be set via secrets for:
  - **Code server** authentication (not possible to switch off).
  - **Hugging Face** tokens for model access.
  - **textgen** gradio authentication.

## Hardware Requirements

- **Recommended GPUs**: Nvidia RTX A4500, RTX A5000, A40, L40S etc...
- **Storage**:
  - **Volume**: 80GB (`/workspace`)
  - **Pod Volume**: 5GB

## Image setup

| Component | Version              |
|-------|------|
| OS        | `Ubuntu v24.04 x86_64` |
| Python    | `3.13.3`             |
| CUDA      | `12.8.1`             |
| Textgen    | `4.9`               |
| Code-Server | `latest`               |

## Available Images

### Base Images

#### ls250824/python-cuda-ubuntu-develop

[![Docker Image Version](https://img.shields.io/docker/v/ls250824/python-cuda-ubuntu-develop)](https://hub.docker.com/r/ls250824/python-cuda-ubuntu-develop)

`run-textgen` is built from `ls250824/python-cuda-ubuntu-develop:23052026`, which is based on `nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04`.

The base image provides Ubuntu 24.04, CUDA 12.8.1, cuDNN development libraries, Python 3.13.3 compiled from source, and a virtual environment at `/opt/venv`. It also includes build tools such as `build-essential`, `cmake`, `ninja-build`, `git`, `git-lfs`, and common RunPod utilities. PyTorch is installed later through the textgen requirements, not by the base image.

### Custom Build

```bash
docker pull ls250824/run-textgen:<version>
```

## Environment Variables

### **Authentication Tokens**

| Token        | Environment Variable | Example | Required |
|--------------|----------------------|---------|----------|
| Hugging Face  | `HF_TOKEN`           | token | Optional  |
| Code Server  | `PASSWORD`           | password | Optional |
| text-generation-webui | `GRADIO_AUTH` | user:password | Optional |

## 📦 **GGUF Model Downloads**

| Model Type     | Hugging Face URL Variable | GGUF File Variable       |
|----------------|---------------------------|---------------------------|
| GGUF Model     | `HF_MODEL_GGUF[1-6]`          | `HF_MODEL_GGUF_FILE[1-6]`     |

## 📦 **MMPROJ Downloads (multi modality)**

| Model Type     | Hugging Face URL Variable | GGUF File Variable       |
|----------------|---------------------------|---------------------------|
| GGUF MMPROJ     | `HF_MMPROJ_GGUF[1-6]`          | `HF_MMPROJ_GGUF_FILE[1-6]`     |

## VRAM-dependent GGUF downloads

At startup, the script reads the total memory of every GPU with `nvidia-smi` and uses the largest value. A GPU with more than `VRAM_THRESHOLD` GiB selects HVRAM; all other GPUs select LVRAM. The default threshold is `36` GiB.

| Profile | GGUF Repository | GGUF File | MMPROJ Repository | MMPROJ File |
|---------|-----------------|-----------|-------------------|-------------|
| HVRAM | `HF_MODEL_HVRAM_GGUF[1-6]` | `HF_MODEL_HVRAM_GGUF_FILE[1-6]` | `HF_MODEL_HVRAM_MMPROJ_GGUF[1-6]` | `HF_MODEL_HVRAM_MMPROJ_GGUF_FILE[1-6]` |
| LVRAM | `HF_MODEL_LVRAM_GGUF[1-6]` | `HF_MODEL_LVRAM_GGUF_FILE[1-6]` | `HF_MODEL_LVRAM_MMPROJ_GGUF[1-6]` | `HF_MODEL_LVRAM_MMPROJ_GGUF_FILE[1-6]` |

Only variables belonging to the selected profile are downloaded. The existing `HF_MODEL_GGUF[1-6]` and `HF_MMPROJ_GGUF[1-6]` variables remain VRAM-independent and are always processed. Set `VRAM_THRESHOLD` to change the boundary.

## 🤖 **Transformers Model Downloads**

| Model Type              | Hugging Face URL Variable | Destination Subfolder Variable | Include Filter Variable | Exclude Filter Variable |
|-------------------------|----------------------------|----------------------------------|-------------------------|-------------------------|
| Transformers   | `HF_MODEL[1-6]`                | `HF_MODEL_DIR[1-6]`                 | `HF_MODEL_INCLUDE[1-6]` | `HF_MODEL_EXCLUDE[1-6]` |

`HF_MODEL_INCLUDE[1-6]` and `HF_MODEL_EXCLUDE[1-6]` are optional and map to `hf download --include` and `hf download --exclude`. If no destination subfolder is set, filtered files are downloaded into `/workspace/textgen/user_data/models/`.

### Hugging Face download behavior

All Hugging Face model downloads start with the Xet backend. Before downloading, the script performs an `hf download --dry-run` to report the expected total size. During the transfer, RunPod logs show downloaded gigabytes and transfer speed. If the download has no output or file growth for 300 seconds, the stalled process is stopped and retried automatically with Xet disabled (plain HTTP).

| Environment Variable | Description | Default |
|----------------------|-------------|---------|
| `HF_DOWNLOAD_STALL_TIMEOUT` | Seconds without download activity before the current attempt is stopped | `300` |
| `HF_DOWNLOAD_KILL_AFTER` | Grace period in seconds before a stalled process is force-killed | `30` |

## 🤖 **EXL Model Downloads**

| Model Type            |    Hugging Face URL Variable | Revision | Destination Subfolder Variable |
|-------------------------|----------|------------------|----------------------------------|
| EXL    | `HF_EXL[1-6]`  |  `HF_EXL_REVISION[1-6]`  |  `HF_EXL_DIR[1-6]`                 |

## Connection options

textgen is checked locally on port `7860` before model provisioning continues. `TEXTGEN_START_MAX_TRIES` controls the maximum number of checks, with five seconds between attempts; the default is `60` (about five minutes).

### Services

| Service         | Port          |
|-----------------|---------------|
| **Code Server** | `9000` (HTTP) |
| **SSH/SCP**     | `22`   (TCP)  |
| **Gradio**      | `7860` (HTTP) |

## Website models

- [Hugging Face](https://huggingface.co/)

## Websites software Github

- [Code server](https://github.com/coder/code-server)
- [textgen](https://github.com/oobabooga/textgen)

## Manual provisioning

[Example RunPod templates](documentation/runpod-env-templates.md)

## Building the Docker Image

| Option         | Description                                         | Default                |
|----------------|-----------------------------------------------------|------------------------|
| `--username`   | Docker Hub username                                 | Current user           |
| `--tag`        | Tag to use for the image                            | Today's date           |
| `--latest`     | If specified, also tags and pushes as `latest`      | Not enabled by default |

### Build & push Command

Run the following command to clone the repository and build the image:

```bash
git clone https://github.com/jalberty2018/run-textgen.git
cp run-textgen/build_docker.py ..

export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1

python build_docker.py \
--username=<your_dockerhub_username> \
--tag=<custom_tag> \
run-textgen
```

Note: If you want to push the image with the latest tag, add the `--latest` flag at the end.

