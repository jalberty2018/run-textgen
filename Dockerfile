# syntax=docker/dockerfile:1.7
FROM ls250824/python-pytorch-cuda-ubuntu-develop:23052026

# Install code-server
RUN curl -fsSL https://code-server.dev/install.sh | sh

# Install oobabooga
RUN git clone --depth=1 https://github.com/oobabooga/textgen.git /textgen

WORKDIR /textgen

# Requirements installeren, maar torch zelf niet opnieuw laten overschrijven
RUN cp requirements/full/requirements.txt /tmp/requirements-full.txt && \
    grep -v -E '^[[:space:]]*(torch|torchvision|torchaudio|flash-attn|flash_attn|exllamav3)([<>=!~ ]|$)' \
      /tmp/requirements-full.txt > /tmp/requirements-patched.txt && \
    python -m pip install -r /tmp/requirements-patched.txt

# Set working directory
WORKDIR /

# Copy scripts and make them executable
COPY --chmod=755 start.sh onworkspace/textgen-on-workspace.sh onworkspace/readme-on-workspace.sh /

# Copy documentation with appropriate permissions
COPY --chmod=644 documentation/README.md /README.md

# Set workspace directory
WORKDIR /workspace

# Cache directory for Hugging Face
ENV HF_HOME=/workspace/cache

# Expose ports for Gradio, code-server
EXPOSE 7860 9000 

# Labels
LABEL org.opencontainers.image.title="oobabooga textgen" \
      org.opencontainers.image.description="Pytorch 2.9.0 CUDA 12.8.1 develop + Ubuntu 24.04 + code-server + ai-textgen" \
      org.opencontainers.image.source="https://hub.docker.com/r/ls250824/run-textgen" \
      org.opencontainers.image.licenses="MIT"

# Tests

RUN which python && \
    which pip && \
    python --version && \
    python -c "import sys; print(sys.prefix)"

RUN python - <<'PY'
import torch
print("torch:", torch.__version__)
print("cuda build:", torch.version.cuda)
print("cuda available:", torch.cuda.is_available())
PY

# Start script
CMD [ "/start.sh" ]
