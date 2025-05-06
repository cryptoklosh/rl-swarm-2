# syntax = docker/dockerfile:1.4

FROM nvidia/cuda:12.2.0-devel-ubuntu20.04

WORKDIR /root

# 1. Prevent tzdata prompts and install system/build dependencies
ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      build-essential \
      cmake \
      ninja-build \
      python3-dev \
      wget curl git \
      python3 python3-venv python3-pip \
      nodejs && \
    rm -rf /var/lib/apt/lists/*

# 2. Ensure nvcc & CUDA are on PATH
ENV CUDA_HOME=/usr/local/cuda
ENV PATH=${CUDA_HOME}/bin:${PATH}
ENV LD_LIBRARY_PATH=${CUDA_HOME}/lib64:${LD_LIBRARY_PATH}
RUN nvcc --version

# 3. Install GPU-enabled PyTorch (CUDA 12.2)
RUN pip3 install --no-cache-dir \
      torch torchvision torchaudio \
      --extra-index-url https://download.pytorch.org/whl/cu122

# 4. Pre-install packaging and build tools so flash-attn’s setup.py can run
RUN pip3 install --no-cache-dir \
      packaging setuptools wheel  \
 && pip3 install --no-cache-dir cython numpy

# 5. Build FlashAttention with no isolation (uses host env)
RUN pip3 install --no-cache-dir flash-attn --no-build-isolation

# 6. Node.js & Yarn setup for frontend
ADD https://deb.nodesource.com/setup_23.x nodesource_setup.sh
RUN chmod +x nodesource_setup.sh && ./nodesource_setup.sh && \
    apt-get update && \
    apt-get install -y --no-install-recommends nodejs && \
    npm install --global yarn && \
    rm -rf /var/lib/apt/lists/* nodesource_setup.sh

WORKDIR /root/modal-login
ENV YARN_CACHE_FOLDER=/root/.yarn
RUN yarn config set cache-folder $YARN_CACHE_FOLDER
COPY modal-login/package.json modal-login/package-lock.json ./
RUN --mount=type=cache,target=$YARN_CACHE_FOLDER yarn install

# 7. Cloudflared & Entrypoint
ADD https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
    /usr/local/bin/cloudflared
RUN chmod +x /usr/local/bin/cloudflared

WORKDIR /root
COPY . .
RUN chmod +x ./entrypoint.sh
ENTRYPOINT [ "/root/entrypoint.sh" ]
