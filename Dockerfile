FROM debian:12
WORKDIR /root
RUN apt-get update && apt-get install -y python3 python-is-python3 python3-venv python3-pip nodejs npm curl
RUN npm install --global yarn

COPY . .
RUN cd modal-login && \
    yarn install && \
    yarn upgrade && \
    yarn add next@latest && \
    yarn add viem@latest && \
    cd ..

RUN pip3 install -r requirements-hivemind.txt --break-system-packages && \
    pip3 install -r requirements.txt --break-system-packages

RUN chmod +x ./entrypoint.sh
ENTRYPOINT [ "/root/entrypoint.sh" ]