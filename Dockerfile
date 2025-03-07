# syntax = docker/dockerfile:experimental
FROM ubuntu:22.04
WORKDIR /
COPY ./bin/manager .
USER 9443:9443
ENTRYPOINT ["/manager"]
