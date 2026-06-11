# syntax=docker/dockerfile:1.7
FROM ls250824/python-cuda-ubuntu-develop:23052026

# Install oobabooga
RUN --mount=type=cache,target=/root/.cache/git \
git clone --depth=1 https://github.com/oobabooga/textgen.git /textgen

WORKDIR /textgen

# Checkout textgen release version 4.9
RUN git fetch --unshallow && git checkout f9df9be98267a79b57617d287d6d0638823116d4

RUN --mount=type=cache,target=/root/.cache/pip \
python -m pip install -r requirements/full/requirements.txt

# Set working directory
WORKDIR /

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
      org.opencontainers.image.description="Python 2.13 + cuda 12.8.1 + Ubuntu 24.04 + code-server + textgen" \
      org.opencontainers.image.source="https://hub.docker.com/r/ls250824/run-textgen" \
      org.opencontainers.image.licenses="MIT"

# Tests

RUN which python && \
    which pip && \
    python --version && \
    python -c "import sys; print(sys.prefix)"

# Start script
CMD [ "/start.sh" ]
