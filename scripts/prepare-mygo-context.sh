#!/usr/bin/env bash
set -euo pipefail

source_root=${MYGO_SOURCE:-../../mygo}
destination=${MYGO_CONTEXT_DIR:-.build/mygo}

if [[ ! -f "$source_root/go.mod" ]]; then
  echo "MyGO checkout not found at $source_root" >&2
  echo "Set MYGO_SOURCE to the MyGO repository root." >&2
  exit 1
fi

case "$destination" in
  ""|"/"|"."|"..")
    echo "refusing unsafe MYGO_CONTEXT_DIR: $destination" >&2
    exit 1
    ;;
esac

if [[ "$(realpath -m "$destination")" == "$(realpath -m "$source_root")" ]]; then
  echo "refusing to overwrite the MyGO source checkout: $destination" >&2
  exit 1
fi

rm -rf -- "$destination"
mkdir -p "$destination"

cp "$source_root/go.mod" "$source_root/go.sum" "$destination/"
cp -R "$source_root/prelude" "$destination/prelude"
cp -R "$source_root/lib" "$destination/lib"
cp -R "$source_root/cmd" "$destination/cmd"
cp -R "$source_root/internal" "$destination/internal"
if [[ -f "$source_root/ebnf.txt" ]]; then
  cp "$source_root/ebnf.txt" "$destination/ebnf.txt"
fi

echo "Prepared BuildKit MyGO context at $destination"
