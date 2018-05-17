#!/usr/bin/env bash

ts=$(date +%s)

for img in $(docker images "final/*" --format "{{.Repository}}:{{.Tag}}") ; do
  dest="${img#final/}"
  docker tag "${img}" "${DOCKER_SINK}/${dest}"
  docker tag "${img}" "${DOCKER_SINK}/${dest}.${ts}"
  docker push "${DOCKER_SINK}/${dest}"
  docker push "${DOCKER_SINK}/${dest}.${ts}"
done

