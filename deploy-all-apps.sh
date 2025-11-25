#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# List each app directory relative to this repo root
apps=(
    "../joeyguerra/joeyguerra"
    "../joeyguerra/coppellfornewtech"
	"../logprojector/website"
    "../joeyguerra/lis7s"
    "../fieldmappings/website"
)

if [ ${#apps[@]} -eq 0 ]; then
	echo 'No app directories configured in deploy-all-apps.sh' >&2
	exit 1
fi

for app in "${apps[@]}"; do
	app_path="$ROOT_DIR/$app"
	if [ ! -d "$app_path" ]; then
		echo "Skipping $app because $app_path does not exist" >&2
		continue
	fi

	echo "Installing dependencies and deploying $app"
	pushd "$app_path" >/dev/null
	npm install
	KUBE_CONTEXT=${KUBE_CONTEXT:-k3d-local} \
	KUBE_CLUSTER=${KUBE_CLUSTER:-local} \
	npm run push
	popd >/dev/null
done
