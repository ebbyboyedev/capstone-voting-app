#!/bin/sh

curl -sS -X POST --data "vote=b" http://localhost:8080 > /dev/null
sleep 10

COUNT=$(docker compose exec -T db psql -U postgres -t -A -c "SELECT COUNT(*) FROM votes;")

if [ "$COUNT" = "1" ]; then
  echo "Test passed"
  exit 0
else
  echo "Test failed: expected 1 vote, found $COUNT"
  exit 1
fi