# Pod image

## **Hugging Face**

```bash
export HF_TOKEN="xxxxx"
hf download model model_name.safetensors --local-dir /workspace
```

```bash
hf auth login --token xxxxx
```

Automatic model provisioning first uses the Xet backend and retries with plain HTTP if the transfer fails or stalls. The script performs a dry run to show the expected total size and reports download growth and speed in the RunPod logs.

| Environment Variable | Description | Default |
|----------------------|-------------|---------|
| `HF_DOWNLOAD_STALL_TIMEOUT` | Seconds without download activity before the current attempt is stopped | `300` |
| `HF_DOWNLOAD_KILL_AFTER` | Grace period in seconds before a stalled process is force-killed | `30` |

## VRAM-dependent model selection

The largest GPU detected with `nvidia-smi` selects the download profile. More than `VRAM_THRESHOLD` GiB selects `HVRAM`; the default threshold is `36`. Otherwise `LVRAM` is selected.

Use `HF_MODEL_HVRAM_GGUF[1-6]` and `HF_MODEL_HVRAM_GGUF_FILE[1-6]` for high-VRAM GGUF files, or replace `HVRAM` with `LVRAM` for low-VRAM files. Multimodal projectors use `HF_MODEL_HVRAM_MMPROJ_GGUF[1-6]` and `HF_MODEL_HVRAM_MMPROJ_GGUF_FILE[1-6]`, with equivalent `LVRAM` variables. Generic GGUF and MMPROJ variables are always processed.

## Utilities

```bash
nvtop      # GPU Monitoring
nvidia-smi # GPU information
htop       # Process Monitoring
mc         # Midnight Commander (file manager)
nano       # Text Editor
ncdu       # Clean up
unzip      # Uncompress
7z         # Archiving
runpodctl  # runpod pod management
```
