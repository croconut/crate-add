#!/bin/bash

#dependency check
if  [[ "$(which jq)" == "" ]] || [[ "$(which curl)" == "" ]] || [[ "$(which tail)" == "" ]] || [[ "$(which awk)" == "" ]] || [[ "$(which grep)" == "" ]] || [[ "$(which sed)" == "" ]] || [[ "$(which tr)" == "" ]]; then
  echo -en "not all dependencies installed, recommended to run: \n\nsudo apt-get update && sudo apt-get install jq curl tail sed awk grep tr\n\n"
  exit 1
fi

SCRIPT_NAME="crate-dependencies"
VERSION="1.0.0"
COMMANDS=(add remove)
#also commands that don't take any kind of action
META_COMMANDS=(help version list)
DEP_FILENAME=Cargo.toml
SWAP_FILENAME=Cargo.toml.swp

DEP_REGEX="^[[:space:]]*\[dependencies\]*"
DEP_NAME="[dependencies]"
DEV_DEP_REGEX="^[[:space:]]*\[dev\-dependencies\]*"
DEV_DEP_NAME="[dev-dependencies]"
CURRENT_DEP_REGEX="$DEP_REGEX"
CURRENT_DEP_NAME="$DEP_NAME"

print_commands() {
  echo "Available commands are:"
  echo "${COMMANDS[@]} ${META_COMMANDS[@]}"
  echo 
  echo "supports adding and removing dependencies as well as any normal cargo command (in particular update and build)"
  echo "add dependencies with crate-add add <crate-name1> <crate-name2> ..."
  echo "remove normal dependencies with crate-add remove <crate-name1> ..."
  echo "currently only adds lastest version of crate to dependency list"
}

print_help() {
  echo
  echo "$SCRIPT_NAME helps manage dependencies for rust projects"
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
  "add")
    echo "$2 already installed with version: $3, skipping"
    return 0
    ;;
  "remove")
    echo "removed $2 v$3"
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
  shift
  ARGS=($@)
  case $command in
  "add")
    for i in ${ARGS[@]}; do
      checkfile=$(construct_endpoint "$i")
      curl_result=$(curl -s "https://raw.githubusercontent.com/rust-lang/crates.io-index/master/$checkfile")
      if [[ -z $(echo "$curl_result" | grep -oE "^[3-5]+[0-9]*") ]]; then
        last_version_json=$(echo "$curl_result" | tail -n1)
        last_version=$(echo "$last_version_json" | jq '.vers')
        # dont add if it's yanked
        yanked=$(echo "$last_version_json" | jq '.yanked')
        [[ "$yanked" == "true" ]] && echo "$i is no longer available" && continue
        echo "adding $i = $last_version to dependencies"
        echo "$i = $last_version" >>$SWAP_FILENAME
      else
        echo "package not found for: $i"
      fi
      sleep 1s
    done
    ;;
  "remove")
    [[ ! -z "${ARGS[@]}" ]] && echo "nothing to remove for crates: ${ARGS[@]}"
    ;;
  *)
    echoerr "unhandled command"
    ;;
  esac
}

OPTIND=1

ARGS=$(getopt -o 'h:v::d' --long 'help:,version::,verbose::,dev' -- "$@") || exit
eval "set -- $ARGS"

LISTMODE=""

while true; do
  case $1 in
  --version)
    print_version
    ;;
  -v | --verbose)
    #TODO
    set -x
    shift
    ;;
  -h | --help)
    print_help
    ;;
  -d | --dev)
    CURRENT_DEP_REGEX="$DEV_DEP_REGEX"
    CURRENT_DEP_NAME="$DEV_DEP_NAME"
    shift
    ;;
  --)
    shift
    break
    ;;
  *)
    echoerr "abnormal error with parsing options"
    ;; # error
  esac
done

ARGS=($@)

if [[ "$1" == "${META_COMMANDS[0]}" ]]; then
  print_help
fi

if [[ "$1" == "${META_COMMANDS[1]}" ]]; then
  print_version
fi

if [[ "$1" == "${META_COMMANDS[2]}" ]]; then
  LISTMODE="1"
  shift
fi

if [[ -z "$LISTMODE" ]]; then

  if [[ -z $@ ]]; then
    echoerr "missing command and/or crate"
  fi

  command=$1
  shift

  if [[ ! -z $(echo "${META_COMMANDS[@]}" | grep -ow "$command") ]]; then
    case $command in
    "${META_COMMANDS[0]}")
      print_version
      ;;
    "${META_COMMANDS[1]}")
      print_help
      ;;
    "${META_COMMANDS[2]}")
      LISTMODE="1"
      ;;
    *)
      echoerr "unhandled meta command"
      ;; # error
    esac
  fi

  if [[ -z $(echo "${COMMANDS[@]}" | grep -ow "$command") ]]; then
    echo $(cargo $command $@)
    exit 0
  fi

  if [[ -z $@ ]]; then
    echoerr "this command requires at least one argument"
  fi

else
  echo "Current $CURRENT_DEP_NAME:"
fi

DEPFILE=$(parent-find "$DEP_FILENAME" "$PWD")

if [[ -z $DEPFILE ]]; then
  echoerr "could not find \`$DEP_FILENAME\` in \`$PWD\` or any parent directory"
fi

crates=($@)

>$SWAP_FILENAME
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
        crate_found "$command" "$i" "$version" && echo $line >>$SWAP_FILENAME
        break
      fi
    done
    # removing crate as already handled if matched, or we write the line since we're not dealing with that crate
    [[ -z "$matched" ]] && [[ ! -z "$line" ]] && echo $line >>$SWAP_FILENAME
    [[ ! -z "$matched" ]] && crates=(${crates[@]/$matched/})
  else
    # when we haven't found the dependencies we're looking for yet, insert to the swap file
    echo $line >>$SWAP_FILENAME
    parse=$(echo "$line" | grep -Eo "$CURRENT_DEP_REGEX")
  fi
done <$DEPFILE

[[ ! -z "$LISTMODE" ]] && rm $SWAP_FILENAME && exit 0

#no section was found, need to create it at end of file
[[ -z "$parse" ]] && echo >>$SWAP_FILENAME && echo "$CURRENT_DEP_NAME" >>$SWAP_FILENAME 

run_on_uninstalled "$command" "${crates[@]}"

parse=""
# write lines to file after the dependencies
while IFS= read line || [ -n "$line" ]; do
  if [[ ! -z "$parse" ]]; then
    if [[ -z "$parse2" ]]; then 
      parse2=$(echo "$line" | grep -Eo "^[[:space:]]*\[")
      [[ ! -z "$parse2" ]] && echo >>$SWAP_FILENAME && echo "$line" >>$SWAP_FILENAME
    else
      echo "$line" >>$SWAP_FILENAME
    fi
  else
    parse=$(echo "$line" | grep -Eo "$CURRENT_DEP_REGEX")
  fi
done <$DEPFILE

while [[ -z $(tail -n2 $SWAP_FILENAME) ]]; do 
  sed -i \$d $SWAP_FILENAME
done

cat $SWAP_FILENAME >$DEPFILE
rm $SWAP_FILENAME
