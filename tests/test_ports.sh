for port in 26657 26656 26658 8545 8546 8551 30303 9101 26660 3500 9090 9091; do
  if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "OPEN  $port  $(lsof -nP -iTCP:"$port" -sTCP:LISTEN | awk 'NR==2 {print $1, $2}')"
  else
    echo "CLOSED $port"
  fi
done