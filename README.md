# Run oobabooga textgen on RunPod

[![Docker Image Version](https://img.shields.io/docker/v/ls250824/run-textgen)](https://hub.docker.com/r/ls250824/run-textgen)

## This pod downloads models as specified in the **environment variables**

- Models are automatically downloaded based on the specified paths in the environment configuration.  
- Authentication credentials can be set via secrets for:  
  - **Code server** authentication (not possible to switch off). 
  - **Hugging Face** tokens for model access.
  - **textgen** gradio authentication.  

## Hardware Requirements  
 
- **Recommended GPUs**: Nvidia RTX A4500, RTX A5000, A40, L40S etc...
- **Storage**:  
  - **Volume**: 80GB (`/workspace`)  
  - **Pod Volume**: 5Gb  
  
## Image setup

| Component | Version              |
|-------|------|
| OS        | `Ubuntu v24.04 x86_64` |
| Python    | `3.13.x`             |
| PyTorch   | `2.9.0`              |
| CUDA      | `12.8.1`             |
| Triton    | `3.5.1`               |

## Available Images

### Base Images 

#### ls250824/pytorch-cuda-ubuntu-runtime
	
[![Docker Image Version](https://img.shields.io/docker/v/ls250824/python-pytorch-cuda-ubuntu-develop)](https://hub.docker.com/r/ls250824/python-pytorch-cuda-ubuntu-develop)

### Custom Build: 

```bash
docker pull ls250824/run-textgen:<version>
```

## Environment Variables  

### **Authentication Tokens**  

| Token        | Environment Variable | Example | Required |
|--------------|----------------------|---------|----------|
| Hugging face  | `HF_TOKEN`           | token | Optional  | 
| Code Server  | `PASSWORD`           | password | Optional |
| text-generation-webui       | `GRADIO_AUTH`        | user:password | Optional |

## 📦 **GGUF Model Downloads**

| Model Type     | Hugging Face URL Variable | GGUF File Variable       |
|----------------|---------------------------|---------------------------|
| GGUF Model     | `HF_MODEL_GGUF[1-6]`          | `HF_MODEL_GGUF_FILE[1-6]`     |

## 📦 **MMPROJ Downloads (multi modality)**

| Model Type     | Hugging Face URL Variable | GGUF File Variable       |
|----------------|---------------------------|---------------------------|
| GGUF MMPROJ     | `HF_MMPROJ_GGUF[1-6]`          | `HF_MMPROJ_GGUF_FILE[1-6]`     |

## 🤖 **Transformers Model Downloads**

| Model Type              | Hugging Face URL Variable | Destination Subfolder Variable |
|-------------------------|----------------------------|----------------------------------|
| Transformers   | `HF_MODEL[1-6]`                | `HF_MODEL_DIR[1-6]`                 |

## 🤖 **EXL Model Downloads**

| Model Type            |    Hugging Face URL Variable | Revision | Destination Subfolder Variable |
|-------------------------|----------|------------------|----------------------------------|
| EXL    | `HF_EXL1`  |  `HF_EXL_REVISION[1-6]`  |  `HF_EXL_DIR[1-6]`                 |


## Connection options 

### Services

| Service         | Port          |
|-----------------|---------------| 
| **Code Server** | `9000` (HTTP) |
| **SSH/SCP**     | `22`   (TCP)  |
| **Gradio**      | `7860` (HTTP) |

## Website models

- [Huggingface](https://huggingface.co/)

## Websites software Github

- [Code server](https://github.com/coder/code-server)
- [textgen](https://github.com/oobabooga/textgen)

## Manual provisioning

[example models](provisioning/provisioning.md)

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
cp run-textgen/build-docker.py ..

export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1

python build-docker.py \
--username=<your_dockerhub_username> \
--tag=<custom_tag> \ 
run-textgen
```

Note: If you want to push the image with the latest tag, add the --latest flag at the end.




