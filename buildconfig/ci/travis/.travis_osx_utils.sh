#!/bin/bash

function fail {
  echo $1 >&2
  exit 1
}

function retry {
  local n=1
  local max=5
  local delay=2
  while true; do
    "$@" && break || {
      if [[ $n -lt $max ]]; then
        ((n++))
        echo "Command failed. Attempt $n/$max:"
        sleep $delay;
      else
        fail "The command has failed after $n attempts."
      fi
    }
  done
}

function prevent_stall {
    while kill -0 "$!" 2> /dev/null
    do
        echo "Waiting..."
        sleep 5
    done
}

function install_or_upgrade {
  if [[ ! "$1" ]]; then
    echo "Called install_or_upgrade with no args; do nothing."
    return 0
  fi

  local outdated=$(brew outdated | grep -m 1 "$1")
  if [[ ! "$outdated" ]] && (brew ls --versions "$1" >/dev/null); then
    echo "$1 is already installed and up to date."
    return 0
  fi

  local deps=""
  local bottled=$(brew info "$1" | grep -m 1 "(bottled)")
  if [[ "$bottled" ]]; then
    deps=$(brew deps --1 "$1")
  else
    deps=$(brew deps --1 --include-build "$1")
  fi
  if [[ "$deps" ]]; then
    echo -n "$1 dependencies: "
    echo $deps
    while read -r dependency; do
      echo "$1: Install dependency $dependency."
      install_or_upgrade "$dependency" ${UNIVERSAL_FLAG}
    done <<< "$deps"
  fi

  if [[ "$outdated" ]]; then
    echo "$1 is installed but outdated."
    if [[ "$bottled" ]]; then
      echo "$1: Found bottle."
      retry brew uninstall --ignore-dependencies "$1"
      retry brew install "$@"
      return 0
    else
      if [[ ! "$UPDATE_UNBOTTLED" ]] || [[ "$UPDATE_UNBOTTLED" = "0" ]]; then
        echo "$1: skipping update. (UPDATE_UNBOTTLED = 0)"
        return 0
      fi
      brew uninstall --ignore-dependencies "$1"
    fi
  else
    echo "$1 is not installed."
    if [[ "$bottled" ]]; then
      echo "$1: Found bottle."
      retry brew install "$@"
      return 0
    fi
  fi

  echo "$1: Found no bottle. Let's build one."

  retry brew install --build-bottle "$@"
  brew bottle --json "$1"
  # TODO: ^ first line in stdout is the bottle file
  # use instead of file cmd. json file has a similar name. "| head -n 1"?
  local jsonfile=$(find . -name $1*.bottle.json)
  brew uninstall --ignore-dependencies "$1"

  local bottlefile=$(find . -name $1*.tar.gz)
  echo "brew install $bottlefile"
  brew install "$bottlefile"

  # Add the bottle info into the package's formula
  echo "brew bottle --merge --write $jsonfile"
  brew bottle --merge --write "$jsonfile"

  # Path to the cachefile will be updated now
  local cachefile=$(brew --cache $1)
  echo "Copying $bottlefile to $cachefile..."
  cp -f "$bottlefile" "$cachefile"

  # save bottle info
  echo "Copying $jsonfile to $HOME/HomebrewLocal/json..."
  mkdir -p "$HOME/HomebrewLocal/json"
  cp -f "$jsonfile" "$HOME/HomebrewLocal/json/"

  echo "Saving bottle path to to $HOME/HomebrewLocal/path/$1..."
  mkdir -p "$HOME/HomebrewLocal/path"
  echo "$cachefile" > "$HOME/HomebrewLocal/path/$1"
}