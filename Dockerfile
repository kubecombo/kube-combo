# syntax = docker/dockerfile:experimental
FROM ubuntu:24.04
WORKDIR /
COPY ./bin/controller .
USER 9443:9443
ENTRYPOINT ["/controller"]
