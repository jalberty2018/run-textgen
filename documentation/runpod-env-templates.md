# Runpod templates

## [Sulphur](https://huggingface.co/SulphurAI/Sulphur-2-base/tree/main/prompt_enhancer)

```bash
HF_TOKEN="{{ RUNPOD_SECRET_HF_TOKEN_WRITE }}"
PASSWORD="{{ RUNPOD_SECRET_CODE-SERVER-NEW }}"
GRADIO_AUTH="{{ RUNPOD_SECRET_Gradio_auth }}"
HF_MODEL_GGUF1=SulphurAI/Sulphur-2-base
HF_MODEL_GGUF_FILE1=prompt_enhancer/sulphur_prompt_enhancer_model-q8_0.gguf
HF_MMPROJ_GGUF1=SulphurAI/Sulphur-2-base
HF_MMPROJ_GGUF_FILE1=prompt_enhancer/mmproj-BF16.gguf
```

## [Dolphin 3.0 Llama](https://huggingface.co/skilledu/Dolphin3.0-Llama3.1-8B-abliterated)

```bash
HF_TOKEN="{{ RUNPOD_SECRET_HF_TOKEN_WRITE }}"
PASSWORD="{{ RUNPOD_SECRET_CODE-SERVER-NEW }}"
GRADIO_AUTH="{{ RUNPOD_SECRET_Gradio_auth }}"
HF_MODEL1=skilledu/Dolphin3.0-Llama3.1-8B-abliterated
HF_MODEL_DIR1=dolphin-llama
```

## [Dolphin Mistral Venice](https://huggingface.co/bartowski/cognitivecomputations_Dolphin-Mistral-24B-Venice-Edition-GGUF)

```bash
HF_TOKEN="{{ RUNPOD_SECRET_HF_TOKEN_WRITE }}"
PASSWORD="{{ RUNPOD_SECRET_CODE-SERVER-NEW }}"
GRADIO_AUTH="{{ RUNPOD_SECRET_Gradio_auth }}"
HF_MODEL_GGUF1=bartowski/cognitivecomputations_Dolphin-Mistral-24B-Venice-Edition-GGUF
HF_MODEL_GGUF_FILE1=cognitivecomputations_Dolphin-Mistral-24B-Venice-Edition-Q6_K_L.gguf
```

## [Dolphin mistral Venice literorica vision](https://huggingface.co/alexnt2/dolphin-mistral-24b-venice-edition-literotica)

```bash
HF_TOKEN="{{ RUNPOD_SECRET_HF_TOKEN_WRITE }}"
PASSWORD="{{ RUNPOD_SECRET_CODE-SERVER-NEW }}"
GRADIO_AUTH="{{ RUNPOD_SECRET_Gradio_auth }}"
HF_MODEL_GGUF1=alexnt2/dolphin-mistral-24b-venice-edition-literotica
HF_MODEL_GGUF_FILE1=Dolphin-Mistral-24B-Venice-Edition.Q6_K.gguf
HF_MMPROJ_GGUF1=alexnt2/dolphin-mistral-24b-venice-edition-literotica
HF_MMPROJ_GGUF_FILE1=Dolphin-Mistral-24B-Venice-Edition.BF16-mmproj.gguf
```