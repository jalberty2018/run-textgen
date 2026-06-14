# Run textgen on RunPod

## This pod downloads models as specified in the **environment variables**

- Models are automatically downloaded based on the specified paths in the environment configuration.
- Authentication credentials can be set via secrets for:
  - **Code server** authentication (not possible to switch off).
  - **Hugging Face** tokens for model access.
  - **textgen** gradio authentication.

## Hardware Requirements

- **Recommended GPUs**: RTX A4500, RTX A5000, A40
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

## Base image

`run-textgen` is built from `ls250824/python-cuda-ubuntu-develop:23052026`, which is based on `nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04`.

The base image provides Ubuntu 24.04, CUDA 12.8.1, cuDNN development libraries, Python 3.13.3 compiled from source, and a virtual environment at `/opt/venv`. It includes build tools and common RunPod utilities. PyTorch is installed later through the textgen requirements, not by the base image.

## Environment Variables

### **Authentication Tokens**

| Token        | Environment Variable | Example | Required |
|--------------|----------------------|---------|----------|
| Hugging Face  | `HF_TOKEN`           | token | Optional  |
| Code Server  | `PASSWORD`           | password | Optional |
| textgen       | `GRADIO_AUTH`        | user:password | Optional |

## 📦 **GGUF Model Downloads**

| Model Type     | Hugging Face URL Variable | GGUF File Variable       |
|----------------|---------------------------|---------------------------|
| GGUF Model     | `HF_MODEL_GGUF[1-6]`          | `HF_MODEL_GGUF_FILE[1-6]`     |

## 📦 **MMPROJ Downloads (multi modality)**

| Model Type     | Hugging Face URL Variable | GGUF File Variable       |
|----------------|---------------------------|---------------------------|
| GGUF MMPROJ     | `HF_MMPROJ_GGUF[1-6]`          | `HF_MMPROJ_GGUF_FILE[1-6]`     |

## 🤖 **Transformers Model Downloads**

| Model Type              | Hugging Face URL Variable | Destination Subfolder Variable | Include Filter Variable | Exclude Filter Variable |
|-------------------------|----------------------------|----------------------------------|-------------------------|-------------------------|
| Transformers   | `HF_MODEL[1-6]`                | `HF_MODEL_DIR[1-6]`                 | `HF_MODEL_INCLUDE[1-6]` | `HF_MODEL_EXCLUDE[1-6]` |

`HF_MODEL_INCLUDE[1-6]` and `HF_MODEL_EXCLUDE[1-6]` are optional and map to `hf download --include` and `hf download --exclude`. If no destination subfolder is set, filtered files are downloaded into `/workspace/textgen/user_data/models/`.


## 🤖 **EXL Model Downloads**

| Model Type            |    Hugging Face URL Variable | Revision | Destination Subfolder Variable |
|-------------------------|----------|------------------|----------------------------------|
| EXL    | `HF_EXL[1-6]`  |  `HF_EXL_REVISION[1-6]`  |  `HF_EXL_DIR[1-6]`                 |

## Connection options

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
