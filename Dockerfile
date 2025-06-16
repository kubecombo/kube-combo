# syntax = docker/dockerfile:experimental
FROM ubuntu:22.04
WORKDIR /
COPY ./bin/controller .
USER 9443:9443
ENTRYPOINT ["/controller"]
