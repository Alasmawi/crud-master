# Shell helpers used by demo.tape (source from the project root).

# Call the API with a JSON content type, pretty-print the body, show the status.
api() {
    local out code
    out=$(curl -s -H "Content-Type: application/json" -w '\n%{http_code}' "$@")
    code=${out##*$'\n'}
    printf '%s\n' "${out%$'\n'*}" | jq . 2>/dev/null || printf '%s\n' "${out%$'\n'*}"
    printf '\033[32m→ HTTP %s\033[0m\n' "$code"
}

# Run a command inside a VM without the ssh noise.
vm() { vagrant ssh "$1" -c "$2" 2>/dev/null; }

# Billing checks on billing-vm.
orders() { vm billing-vm "cd /tmp && sudo -u postgres psql billing_db -c 'SELECT * FROM orders ORDER BY id;'"; }
queue()  { vm billing-vm "sudo rabbitmqctl list_queues -q name messages_ready"; }

# Start the demo from empty tables.
reset_demo() {
    curl -s -X DELETE localhost:3000/api/movies >/dev/null
    vm billing-vm "cd /tmp && sudo -u postgres psql -q billing_db -c 'TRUNCATE orders RESTART IDENTITY;'"
    vm inventory-vm "cd /tmp && sudo -u postgres psql -q movies_db -c 'ALTER SEQUENCE movies_id_seq RESTART;'"
}
