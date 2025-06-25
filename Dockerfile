# syntax = docker/dockerfile:experimental
FROM ubuntu:24.04
WORKDIR /
COPY ./bin/controller manager
USER 9443:9443
ENTRYPOINT ["/manager"]
