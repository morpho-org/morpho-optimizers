#!/usr/bin/env bash

# inspired by https://github.com/odyslam/bash-utils/blob/main/forge-inspect.sh

set -e

generate() {
  file=$1
  if [[ $func == "generate" ]]; then
    echo "Generating storage layout for the following contracts: $contracts"
  fi

  > "$file"

  for contract in ${contracts[@]}
  do
    { echo -e "\n======================="; echo "➡ $contract" ; echo -e "=======================\n"; } >> "$file"
    forge inspect --pretty "$contract" storage-layout >> "$file"
  done
  if [[ $func == "generate" ]]; then
    echo "Storage layout snapshot stored at $file"
  fi
}

func=$1
filename=$2
contracts="${@:3}"


if [[ $func == "check" ]]; then
  echo "Checking storage layout for the following contracts: $contracts"
  new_filename=${filename}.temp
  generate $new_filename
  if ! cmp -s $filename $new_filename ; then
    echo "Storage layout test: fails ❌"
    echo "The following lines are different:"
    diff -a --suppress-common-lines "$filename" "$new_filename"
    rm $new_filename
    exit 1
  else
    echo "Storage layout test: passes ✅"
    rm $new_filename
    exit 0
  fi
elif [[ $func == "generate" ]]; then
  generate "$filename"
else
  echo "Unknown command. Use 'generate' or 'check' as the first argument."
  exit 1
fi
