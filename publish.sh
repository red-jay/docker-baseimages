#!/usr/bin/env bash

ts=$(date +%s)

for img in $(docker images "build/*" --format "{{.Repository}}") ; do
  dist_version="${img##build/}"
  version="${dist_version##*-}"
  dist="${dist_version%-${version}}"
  docker tag "${img}" "${DOCKER_SINK}/${dist}:${version}"
  docker tag "${img}" "${DOCKER_SINK}/${dist}:${version}.${ts}"
  docker push "${DOCKER_SINK}/${dist}:${version}"
  docker push "${DOCKER_SINK}/${dist}:${version}.${ts}"
done

