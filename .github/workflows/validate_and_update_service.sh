#!/bin/bash

set -e

name=$1
sample_file=$2
sample_service=$3
instance_count=$4
version_files=$5
input_version=$6
release_type=$7

#TODO: Validate images exist

### Validate that existing state is consistent before proceeding

# A simplified version of the regexp at https://semver.org/
# Does not include start/end anchors. After the patch version we're more restrictive: either empty or `-rc.<number>`
# Also parenthesis, -, and | have to be escaped.
semver_regexp="\(0\|[1-9][0-9]*\)\.\(0\|[1-9][0-9]*\)\.\(0\|[1-9][0-9]*\)\(\-rc\.[0-9]*\)\?"


# Find the current version, using a sample file file
current_version=$(sed -n 's/.*'"$sample_service"':\('"$semver_regexp"'\)"/\1/p' $sample_file)

current_version_count=$(grep -roh "$current_version" $version_files | wc -l | xargs) #xargs to strip space

if [ "$current_version_count" == "$instance_count" ]; then
  echo "$name currently at version $current_version ($current_version_count eligible instances)"
else
  # Something is off -- all versions should match. We don't know which is correct/which out of date, just that it is inconsistent
  echo "The $name version appears inconsistent! Please fix incorrect files manually and then proceed! Expected $instance_count but found $current_version_count matching versions (searching for $current_version)."
  exit 1
fi

### Validate input
if [ "$input_version" != "" ]; then
  input_semver=$(echo "$input_version" | sed -n 's/\(^'"$semver_regexp"'$\)/\1/p')

  if [ "$input_semver" != "$input_version" ]; then
    echo "$name version was not a valid semver. Is $input_version"
    exit 1
  fi

  is_greater_semver=$(.github/workflows/semver2.sh $input_version $current_version)

  if [ "$is_greater_semver" == "1" ]; then
    if [ "$release_type" == "" ]; then
      echo "$input_version is ahead of $current_version and release is normal. Proceeding"
    else
      echo "$input_version is ahead of $current_version, but release is not normal. Is \"$release_type\". Stopping"
      exit 1
    fi
  elif [ "$is_greater_semver" == "0" ]; then
    # We could invert things a bit so that bounce doesn't require specifying the version, but it's fine really (good
    # to confirm?)
    if [ "$release_type" == "bounce" ]; then
      echo "$input_version equals current version and release is bounce. Proceeding"

      # Expect no changes when updating
      instance_count=0
    else
      echo "$input_version equals current version, but release is not bounce. Is \"$release_type\". Stopping"
      exit 1
    fi
  else
    if [ "$release_type" == "rollback" ]; then
      echo "$input_version is behind $current_version and release is rollback. Proceeding"
    else
      echo "$input_version is behind $current_version, but release is not rollback. Is \"$release_type\". Stopping"
      exit 1
    fi
  fi

else
  echo "input_version was missing. Aborting"
  exit 1
fi

if [[ $(git diff --stat) != '' ]]; then
  echo 'Git working status is dirty already. Aborting'
  exit 1
fi

sed -i 's/'"$current_version"'/'"$input_version"'/g' $version_files

changed_files=$(git diff -U0 | grep '^[+-] ' | wc -l | xargs)
changes=$(( $changed_files / 2))

if [ "$changes" != "$instance_count" ]; then
  echo "Updating the version did not make the expected number of changes (expected $instance_count, but found $changes changes). Aborting"
  exit 1
fi

if [ "$instance_count" == "0" ]; then
  touch allow_empty
fi

git add $version_files

echo "$name $input_version" >> release-commit-msg.txt
