# syntax=docker/dockerfile:1.7
FROM ls250824/python-cuda-ubuntu-develop:23052026

ARG TEXTGEN_VERSION=v4.9
ARG TEXTGEN_COMMIT=f9df9be98267a79b57617d287d6d0638823116d4

# Install oobabooga
RUN --mount=type=cache,target=/root/.cache/git \
git clone --depth=1 https://github.com/oobabooga/textgen.git /textgen

WORKDIR /textgen

# Checkout textgen release v4.9 and verify the expected immutable commit.
RUN git fetch --depth=1 origin tag ${TEXTGEN_VERSION} && \
    git checkout ${TEXTGEN_COMMIT} && \
    test "$(git rev-parse HEAD)" = "${TEXTGEN_COMMIT}"

RUN --mount=type=cache,target=/root/.cache/pip \
python -m pip install -r requirements/full/requirements.txt

# Set working directory
WORKDIR /

# Update Hugging Face CLI and verify the hf command is available
RUN --mount=type=cache,target=/root/.cache/pip \
python -m pip install -U huggingface_hub
RUN hf update && hf version

# Install code-server
RUN curl -fsSL https://code-server.dev/install.sh | sh

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
LABEL org.opencontainers.image.title="oobabooga textgen version 4.9" \
      org.opencontainers.image.description="Python 3.13 + cuda 12.8.1 + Ubuntu 24.04 + code-server + textgen" \
      org.opencontainers.image.source="https://github.com/jalberty2018/run-textgen" \
      org.opencontainers.image.licenses="AGPL-3.0-only"

# Tests

RUN which python && \
    which pip && \
    python --version && \
    python -c "import sys; print(sys.prefix)"

RUN python -c "import torch, triton, importlib, importlib.util as iu; \
print(f'Torch: {torch.__version__}'); \
print(f'Triton: {triton.__version__}'); \
print('CUDA available:', torch.cuda.is_available()); \
print('CUDA version:', torch.version.cuda); \
print('Device:', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'CPU')"

# Start script
CMD [ "/start.sh" ]
