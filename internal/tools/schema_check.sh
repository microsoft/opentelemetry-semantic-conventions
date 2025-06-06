#!/usr/bin/env bash

# This script does some minimal sanity checks of schema files.
# It expects to find a schema file for each version listed in CHANGELOG.md
# since 1.0.0 release.

set -e

BUILD_TOOL_SCHEMAS_VERSION=0.25.0

# List of versions that do not require or have a schema.
declare -a skip_versions=("1.0.0" "1.0.1" "1.1.0" "1.2.0" "1.3.0" "1.6.0")

# Verifies remote availability of a schema file.
#
# If the schema file is available for download, THEN we make sure it is exactly
# what is in the repository.  If the file is not available for download,
# we pass this check.  This is to allow releases to be checked in, where
# a new version is specified but hasn't propagated to the website yet.
#
# Args:
# 1 - version number
verify_remote_availability() {
  local ver="$1"
  echo -n "Ensure published schema file https://opentelemetry.io/schemas/$ver matches local copy... "
  if curl --fail --no-progress-meter https://opentelemetry.io/schemas/$ver > verify$ver 2>/dev/null; then
    diff verify$ver $file && echo "OK, matches" \
      || (echo "Incorrect!" && exit 3)
  else
    echo "Not found"
  fi
  rm verify$ver
}

# Verifies remote availability of a schema file in the current repository.
#
# Args:
# 1 - version number
verify_local_availability() {
  local ver="$1"

  file="$schemas_dir/$ver"
  echo -n "Ensure schema file $file exists... "

  # Check that the schema for the version exists.
  if [ -f "$file" ]; then
    echo "OK, exists."
  else
    echo "FAILED: $file does not exist. The schema file must exist because the version is declared in CHANGELOG.md."
    exit 3
  fi
}

root_dir=$PWD
schemas_dir=$root_dir/schemas

# Find all version sections in CHANGELOG that start with a number in 1..9 range.
grep -o -e '## v[1-9].*\s' $root_dir/CHANGELOG.md | grep -o '[1-9].*' | while read ver; do
  if [[ " ${skip_versions[*]} " == *" $ver "* ]]; then
    # Skip this version, it does not need a schema file.
    continue
  fi

  verify_local_availability "$ver"
  verify_remote_availability "$ver"
done

# Now check the content of all schema files in the ../schemas directory.
for file in $schemas_dir/*; do
  # Filename is the version number.
  ver=$(basename $file)

  echo -n "Checking schema file $file for version $ver... "

  # Check that the version is defined in the schema file.
  if ! grep -q "\s$ver:" $file; then
    echo "FAILED: $ver version definition is not found in $file"
    exit 1
  fi

  # Check that the schema_url matches the version.
  if ! grep -q "schema_url: https://opentelemetry.io/schemas/$ver" $file; then
    echo "FAILED: schema_url is not found in $file"
    exit 2
  fi

  PODMAN_USERNS=keep-id docker run \
      -u $(id -u):$(id -g) \
      -v $schemas_dir:/schemas \
  		docker.io/otel/build-tool-schemas:$BUILD_TOOL_SCHEMAS_VERSION --file /schemas/$ver --version=$ver

  echo "OK"
done
