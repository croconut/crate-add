#!/bin/bash

#dependency checks
if [[ "$(which jq)" == "" ]] || [[ "$(which curl)" == "" ]] || [[ "$(which tail)" == "" ]] || [[ "$(which awk)" == "" ]] || [[ "$(which grep)" == "" ]] || [[ "$(which sed)" == "" ]] || [[ "$(which tr)" == "" ]]; then
  echo -en "not all dependencies installed, recommended to run: \n\nsudo apt-get update && sudo apt-get install jq curl tail sed awk grep tr\n\n"
  exit 1
fi

if [[ "$(which cargo)" == "" ]]; then
  echo "install cargo before using crate-add"
  exit 1
fi

print_commands() {
  echo "Available commands are:"
  echo "${COMMANDS[@]} ${META_COMMANDS[@]}"
  echo
  echo "supports adding and removing dependencies and forwards commands to cargo e.g. 'crate-add install' is the same as 'cargo install'"
  echo "you can also use crate-add pass <cargo_command> to do the same thing"
  echo
  echo "add dependencies with crate-add add <crate-name1> <crate-name2> ..."
  echo "remove dependencies with crate-add remove <crate-name1> ..."
  echo
  echo "dev-dependencies are managed with adev / add-dev for adding and rdev / remove-dev for removing"
  echo
  echo "only the newest crate versions can be added as dependencies"
}

print_help() {
  echo
  echo "$SCRIPT_NAME v$VERSION helps manage dependencies for rust projects"
  echo
  print_commands
  echo
  exit 0
}

print_version() {
  echo
  echo "$SCRIPT_NAME v$VERSION"
  echo
  exit 0
}

#credit: https://stackoverflow.com/questions/2990414/echo-that-outputs-to-stderr
echoerr() {
  printf >&2 "error: %s\n" "$*"
  rm 2>/dev/null "$SWAP_FILENAME" || :
  exit 1
}

#credit: https://unix.stackexchange.com/questions/6463/find-searching-in-parent-directories-instead-of-subdirectories
# will error out if relative path is used instead of absolute
parent-find() {
  local file="$1"
  local dir="$2"

  test -e "$dir/$file" && echo "$dir/$file" && return 0
  [ '/' = "$dir" ] && return 0
  [ "." = "$dir" ] && echoerr "must use full path for parent-find" && return 1

  parent-find "$file" "$(dirname "$dir")"
}

crate_found() {
  case $1 in
  "$BASE_ADD_COMMAND")
    echo "$2 already installed to $4 with version: $3, skipping"
    return 0
    ;;
  "$BASE_REMOVE_COMMAND")
    echo "removed $2 v$3 from $4"
    return 1
    ;;
  *)
    echoerr "unhandled command"
    ;;
  esac
}

construct_endpoint() {
  local filetoget="$1"
  local len=$(echo "$filetoget" | awk '{print length}')

  [[ "$len" -eq "1" ]] && echo "1/$filetoget"
  [[ "$len" -eq "2" ]] && echo "2/$filetoget"
  [[ "$len" -eq "3" ]] && echo "3/${filetoget:0:1}/$filetoget"
  [[ "$len" -gt "3" ]] && echo "${filetoget:0:2}/${filetoget:2:2}/$filetoget"
  return 0
}

run_on_uninstalled() {
  local command=$1
  local depname=$2
  shift
  shift
  ARGS=($@)
  case $command in
  "$BASE_ADD_COMMAND")
    for i in ${ARGS[@]}; do
      checkfile=$(construct_endpoint "$i")
      curl_result=$(curl -s "https://raw.githubusercontent.com/rust-lang/crates.io-index/master/$checkfile")
      if [[ -z $(echo "$curl_result" | grep -oE "^[3-5]+[0-9]*") ]]; then
        last_version_json=$(echo "$curl_result" | tail -n1)
        last_version=$(echo "$last_version_json" | jq '.vers')
        # dont add if it's yanked
        yanked=$(echo "$last_version_json" | jq '.yanked')
        [[ "$yanked" == "true" ]] && echo "$i is no longer available" && continue
        echo "adding $i = $last_version to $depname"
        echo "$i = $last_version" >>"$SWAP_FILENAME"
      else
        echo "package not found for: $i"
      fi
      sleep 1s
    done
    ;;
  "$BASE_REMOVE_COMMAND")
    [[ ! -z "${ARGS[@]}" ]] && echo "nothing to remove from $depname for crates: ${ARGS[@]}"
    ;;
  *)
    echoerr "unhandled command"
    ;;
  esac
}

SCRIPT_NAME="crate-add"
VERSION="1.2.0"
#all commands / meta_commands that end in dev are targetted at dev dependencies
#IMPORTANT: only add and remove commands get to start with a and r respectively
BASE_ADD_COMMAND="a"
BASE_REMOVE_COMMAND="r"
COMMANDS=(add "$BASE_ADD_COMMAND" adev a-dev add-dev adddev remove "$BASE_REMOVE_COMMAND" rdev r-dev remove-dev removedev)
#also commands that don't take any kind of action
META_COMMANDS=(help version pass list l list-dev ldev l-dev listdev)
DEP_FILENAME="Cargo.toml"
SWAP_DIR="/tmp/$SCRIPT_NAME"
SWAP_FILENAME="$SWAP_DIR/Cargo.toml.swp"

DEP_REGEX="^[[:space:]]*\[dependencies\]*"
DEP_NAME="[dependencies]"
DEV_DEP_REGEX="^[[:space:]]*\[dev\-dependencies\]*"
DEV_DEP_NAME="[dev-dependencies]"
CURRENT_DEP_REGEX="$DEP_REGEX"
CURRENT_DEP_NAME="$DEP_NAME"
ORIGINAL_CALL="$0"
LISTMODE=""

command="$1"
ORIGINAL_COMMAND="$1"

[[ -z "$ORIGINAL_COMMAND" ]] && print_help

#credit: https://stackoverflow.com/questions/39305567/bash-implode-array-to-string
metagrep=$(printf "%s|" "${META_COMMANDS[@]}")
metagrep="${metagrep%|}"

if [[ ! -z $(echo "$command" | grep -Eow "^(${META_COMMANDS[0]})$") ]]; then
  print_help
elif [[ ! -z $(echo "$command" | grep -Eow "^(${META_COMMANDS[1]})$") ]]; then
  print_version
elif [[ ! -z $(echo "$command" | grep -Eow "^(${META_COMMANDS[2]})$") ]]; then
  shift
  [[ -z "$@" ]] && echoerr "no command to pass to cargo"
  echo "passing command to cargo"
  echo "cargo $@"
  cargo "$@"
  exit 0
# all other meta commands are just variations of list
elif [[ ! -z $(echo "$command" | grep -Eow "^(${metagrep[@]})$") ]]; then
  LISTMODE="1"
fi

if [[ -z "$LISTMODE" ]]; then

  if [[ -z "$@" ]]; then
    echoerr "missing command and/or crate"
  fi

  #credit: https://stackoverflow.com/questions/39305567/bash-implode-array-to-string
  commandgrep=$(printf "%s|" "${COMMANDS[@]}")
  commandgrep="${commandgrep%|}"

  if [[ -z $(echo "$command" | grep -Eow "^(${commandgrep[@]})$") ]]; then
    echo "Command not found in list for $SCRIPT_NAME: ${commandgrep[@]}"
    echo "Passthrough running:"
    echo "cargo $@"
    cargo "$@"
    exit 0
  fi

  opposite_command="l"

  if [[ ! -z $(echo "$command" | grep -Eo "^($BASE_ADD_COMMAND)*") ]]; then
    command="$BASE_ADD_COMMAND"
    opposite_command="${BASE_REMOVE_COMMAND}dev"
  elif [[ ! -z $(echo "$command" | grep -Eo "^($BASE_REMOVE_COMMAND)*") ]]; then
    command="$BASE_REMOVE_COMMAND"
    opposite_command="${BASE_ADD_COMMAND}dev"
  fi

  shift

  [[ -z $@ ]] && echoerr "$ORIGINAL_COMMAND requires at least one argument"

fi

crates=($@)

DEPFILE=$(parent-find "$DEP_FILENAME" "$PWD")

[[ -z "$DEPFILE" ]] && echoerr "could not find \`$DEP_FILENAME\` in \`$PWD\` or any parent directory"

if [[ ! -z $(echo "$ORIGINAL_COMMAND" | grep -Eo "*dev$") ]]; then
  CURRENT_DEP_NAME="$DEV_DEP_NAME"
  CURRENT_DEP_REGEX="$DEV_DEP_REGEX"
  opposite_command="${opposite_command:0:1}"
fi

[[ ! -z "$LISTMODE" ]] && echo "Current $CURRENT_DEP_NAME:"

#we reverse the call if it's an add to remove the dependency from the dev or vice
#versa and install to the requested one
if [[ -z "$LISTMODE" ]] && [[ "$command" == "$BASE_ADD_COMMAND" ]]; then
  bash "$ORIGINAL_CALL" $opposite_command $@
fi

mkdir -p $SWAP_DIR
>"$SWAP_FILENAME"
touch $SWAP_FILENAME
passed_dep="0"
parse=""
parse2=""
version=""

while IFS= read line || [ -n "$line" ]; do
  if [[ ! -z "$parse" ]]; then
    matched=""
    [[ ! -z $(echo "$line" | grep -Eo "^\[") ]] && break
    [[ ! -z "$LISTMODE" ]] && echo "$line"
    for i in "${crates[@]}"; do
      version=$(echo "$line" | grep -E --line-buffered "^$i[[:space:]]*=" | grep -oP --line-buffered "=[[:space:]]*\K.*" | tr -d '"' | tr -d "'")
      if [[ ! -z $version ]]; then
        matched="$i"
        # here we run the command immediately, we tell line to write based on the return, if remove we would just return 1
        # if add we return 0
        crate_found "$command" "$i" "$version" "$CURRENT_DEP_NAME" && echo $line >>"$SWAP_FILENAME"
        break
      fi
    done
    # removing crate as already handled if matched, or we write the line since we're not dealing with that crate
    [[ -z "$matched" ]] && [[ ! -z "$line" ]] && echo $line >>"$SWAP_FILENAME"
    [[ ! -z "$matched" ]] && crates=(${crates[@]/$matched/})
  else
    # when we haven't found the dependencies we're looking for yet, insert to the swap file
    echo $line >>"$SWAP_FILENAME"
    parse=$(echo "$line" | grep -Eo "$CURRENT_DEP_REGEX")
  fi
done <"$DEPFILE"

[[ ! -z "$LISTMODE" ]] && rm "$SWAP_FILENAME" && exit 0

#no section was found, need to create it at end of file
[[ -z "$parse" ]] && echo >>"$SWAP_FILENAME" && echo "$CURRENT_DEP_NAME" >>"$SWAP_FILENAME"

run_on_uninstalled "$command" "$CURRENT_DEP_NAME" "${crates[@]}"

parse=""
# write lines to file after the dependencies
while IFS= read line || [ -n "$line" ]; do
  if [[ ! -z "$parse" ]]; then
    if [[ -z "$parse2" ]]; then
      parse2=$(echo "$line" | grep -Eo "^[[:space:]]*\[")
      [[ ! -z "$parse2" ]] && echo >>"$SWAP_FILENAME" && echo "$line" >>"$SWAP_FILENAME"
    else
      echo "$line" >>"$SWAP_FILENAME"
    fi
  else
    parse=$(echo "$line" | grep -Eo "$CURRENT_DEP_REGEX")
  fi
done <"$DEPFILE"

while [[ -z $(tail -n1 "$SWAP_FILENAME") ]]; do
  sed -i \$d "$SWAP_FILENAME"
done

cat "$SWAP_FILENAME" >"$DEPFILE"
rm "$SWAP_FILENAME"
