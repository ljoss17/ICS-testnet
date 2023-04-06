# syntax=docker/dockerfile:1

FROM golang:1.18-alpine AS is-builder

ENV PACKAGES curl make git libc-dev bash gcc linux-headers
ENV CGO_ENABLED=0
ENV GOOS=linux

RUN apk add --no-cache $PACKAGES

WORKDIR /downloads
RUN git clone https://github.com/cosmos/interchain-security.git

RUN cd interchain-security && git checkout sainoe/export-genesis && make install

FROM --platform=linux/amd64 debian:bullseye-slim
USER root
WORKDIR /root

RUN apt update && apt install -y jq vim procps net-tools git curl

COPY --from=is-builder /go/bin/interchain-security-pd /usr/local/bin/interchain-security-pd
COPY --from=is-builder /go/bin/interchain-security-cd /usr/local/bin/interchain-security-cd

ADD hermes /usr/local/bin/hermes

RUN chmod +x /usr/local/bin/hermes /usr/local/bin/interchain-security-pd /usr/local/bin/interchain-security-cd

RUN git clone https://github.com/informalsystems/gm

RUN curl -Lo /usr/local/bin/sconfig https://github.com/freshautomations/sconfig/releases/download/v0.1.0/sconfig_linux_amd64
RUN curl -Lo /usr/local/bin/stoml https://github.com/freshautomations/stoml/releases/download/v0.7.0/stoml_linux_amd64
RUN chmod 755 /usr/local/bin/sconfig
RUN chmod 755 /usr/local/bin/stoml

ADD  ./scripts ./scripts
EXPOSE 26658 26648

ENTRYPOINT [ "/bin/bash" ]

