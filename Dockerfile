# syntax = docker/dockerfile:experimental
FROM ubuntu:24.04
WORKDIR /
COPY ./bin/kube-combo-cmd .
RUN ln -s /kube-combo-cmd /controller && \
    ln -s /kube-combo-cmd /pinger

USER 9443:9443
ENTRYPOINT ["/controller"]
