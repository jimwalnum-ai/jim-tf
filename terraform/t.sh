  #!/usr/bin/env bash
     set -euo pipefail

     if [[ $# -ne 2 ]]; then
       echo "Usage: $0 <search_string> <replace_string>" >&2
       exit 1
     fi

     search="$1"
     replace="$2"

     find . -type f -not -path "./.git/*" -print0 |
       xargs -0 perl -pi -e 's/\Q'"$search"'\E/'"$replace"'/g'
