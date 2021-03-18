#!/usr/bin/env bash

set -euox pipefail

sha=$1
sha=${sha::8}
event=$2
pr=$3

tag=quay.io/$QUAY_REPO:sha-$sha
if [[ $event == "pull_request" ]]; then
	QUAY_REPO+=-pr
	tag=quay.io/$QUAY_REPO:pr$pr-sha-$sha
fi

docker images --format '{{.Repository}} {{.Tag}} {{.ID}}' | sort | awk '/ci-image-build/ {printf "%s %s\n", $2, $3}' | while read -r oldtag id; do
	# shellcheck disable=SC2001
	t=$tag-$(sed 's|sha-[0-9a-z]\+-||' <<<"$oldtag")
	docker tag "$id" "$t"
	docker rmi "ci-image-build:$oldtag"
	docker push -q "$t"
done

mapfile -t digests < <(docker images --format '{{.Digest}}' --filter reference="quay.io/$QUAY_REPO" | sort | sed "s|^|quay.io/$QUAY_REPO@|" | tr '\n' ' ')
docker manifest create "$tag" ${digests[@]}
docker manifest push "$tag"

set +x
docker images --format '{{.Tag}}' --filter reference="$tag-*" | sort | while read -r tag; do
	echo "deleting https://quay.io/api/v1/repository/$QUAY_REPO/tag/$tag"
	curl \
		--fail \
		--oauth2-bearer "$QUAY_API_TOKEN" \
		--retry 5 \
		--retry-connrefused \
		--retry-delay 2 \
		--silent \
		-XDELETE \
		"https://quay.io/api/v1/repository/$QUAY_REPO/tag/$tag"
done
