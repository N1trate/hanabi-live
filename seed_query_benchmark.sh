#!/usr/bin/env bash

set -euo pipefail # Exit on errors and undefined variables.

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <comma-separated user IDs> <seed prefix>"
  echo "Example: $0 1234,5678 p2v0s"
  exit 1
fi
USER_IDS="$1"
SEED_PREFIX="$2"

if ! [[ $USER_IDS =~ ^[0-9]+(,[0-9]+)*$ ]]; then
  echo "Error: user IDs must be a comma-separated list of numbers."
  exit 1
fi
if ! [[ $SEED_PREFIX =~ ^[A-Za-z0-9]+$ ]]; then
  echo "Error: user seed prefix must be a alphanumeric (e.g. \"p2v0s\")."
  exit 1
fi

# Get the directory of this script:
# https://stackoverflow.com/questions/59895/getting-the-source-directory-of-a-bash-script-from-within
DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# Import the database information.
ENV_PATH="$DIR/.env"
if [[ ! -f $ENV_PATH ]]; then
  echo "Failed to find the \".env\" file at: $ENV_PATH"
  exit 1
fi
# shellcheck source=/dev/null
source "$ENV_PATH"
if [[ -z ${DB_HOST-} ]]; then
  DB_HOST=localhost
fi
if [[ -z ${DB_PORT-} ]]; then
  DB_PORT=5432
fi

OLD_QUERY="
  SELECT DISTINCT games.seed AS seed
  FROM user_linkages
  JOIN game_participants ON user_linkages.linked_id = game_participants.user_id
  JOIN games ON games.id = game_participants.game_id
  WHERE user_linkages.user_id = ANY ('{$USER_IDS}'::int[])
  UNION DISTINCT
  SELECT DISTINCT games.seed AS seed
  FROM game_participants
  JOIN games ON games.id = game_participants.game_id
  WHERE game_participants.user_id = ANY ('{$USER_IDS}'::int[])
  ORDER BY seed
"

NEW_QUERY="
  SELECT DISTINCT games.seed AS seed
  FROM user_linkages
  JOIN game_participants ON user_linkages.linked_id = game_participants.user_id
  JOIN games ON games.id = game_participants.game_id
  WHERE user_linkages.user_id = ANY ('{$USER_IDS}'::int[])
    AND games.seed LIKE '$SEED_PREFIX%'
  UNION DISTINCT
  SELECT DISTINCT games.seed AS seed
  FROM game_participants
  JOIN games ON games.id = game_participants.game_id
  WHERE game_participants.user_id = ANY ('{$USER_IDS}'::int[])
    AND games.seed LIKE '$SEED_PREFIX%'
"

run_psql() {
  PGPASSWORD="$DB_PASSWORD" psql --host="$DB_HOST" --port="$DB_PORT" \
    --username="$DB_USER" --dbname="$DB_NAME" -X -q -A -t -c "$1"
}

benchmark() {
  local query="$2"
  echo "--- $1 ---"
  echo "Rows returned: $(run_psql "SELECT COUNT(*) FROM ($query) AS q")"
  for i in 1 2 3; do
    local time
    time=$(run_psql "EXPLAIN (ANALYZE, FORMAT JSON) $query" \
      | grep -o '"Execution Time": [0-9.]*' | grep -o '[0-9.]*')
    echo "Run $i: $time ms"
  done
  echo
}

echo "Index on game_participants (user_id): $(run_psql "
  SELECT COALESCE(
    (SELECT indexname FROM pg_indexes
     WHERE tablename = 'game_participants' AND indexdef LIKE '%user_id%' LIMIT 1),
    'none'
  )
")"
echo "game_participants row count (estimate): $(run_psql "
  SELECT reltuples::bigint FROM pg_class where relname = 'game_participants'
")"
echo

benchmark "OLD query (all seeds, ORDER BY)" "$OLD_QUERY"
benchmark "NEW query (prefix filter, no ORDER BY)" "$NEW_QUERY"
