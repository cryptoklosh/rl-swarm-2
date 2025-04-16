# syntax = docker/dockerfile:1.4

FROM debian:12
WORKDIR /root
RUN apt-get update && apt-get install -y python3 python-is-python3 python3-venv python3-pip nodejs npm curl
RUN npm install --global yarn

WORKDIR /root/modal-login
ENV YARN_CACHE_FOLDER=/root/.yarn
RUN yarn config set cache-folder $YARN_CACHE_FOLDER
COPY modal-login/package.json ./package.json
COPY modal-login/package-lock.json ./package-lock.json
RUN --mount=type=cache,mode=0777,target=$YARN_CACHE_FOLDER yarn install && \
    yarn upgrade && \
    yarn add next@latest && \
    yarn add viem@latest && \
    yarn add pino-pretty@latest && \
    yarn add encoding@latest
WORKDIR /root

COPY requirements-hivemind.txt ./requirements-hivemind.txt
COPY requirements.txt ./requirements.txt
RUN --mount=type=cache,target=/root/.cache/pip pip3 install -r requirements-hivemind.txt --break-system-packages
RUN --mount=type=cache,target=/root/.cache/pip pip3 install -r requirements.txt --break-system-packages

COPY . .

RUN chmod +x ./entrypoint.sh
ENTRYPOINT [ "/root/entrypoint.sh" ]