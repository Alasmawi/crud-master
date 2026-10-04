# Terminal recording of crud-master running on the 3 Vagrant VMs.
# Re-record from the project root (VMs must be up):  vhs docs/media/demo.tape
# Requires: vhs (brew install vhs), jq, newman (or npx).

Output docs/media/demo.gif
Output docs/media/demo.mp4

Set Shell zsh
Set FontSize 15
Set Width 1280
Set Height 760
Set Padding 18
Set Theme "Catppuccin Mocha"
Set TypingSpeed 25ms

# --- setup (not recorded): helpers + a clean starting state
Hide
Type "setopt interactivecomments; source docs/media/demo-helpers.sh" Enter
Type "PS1='%F{blue}crud-master%f %# '" Enter
Type "reset_demo" Enter
Sleep 10s
Type "clear" Enter
Show

# --- 1. Infrastructure
Type "# 1. Three VMs, each running its app under PM2" Enter
Sleep 500ms
Type "vagrant status" Enter
Sleep 4s
Type "vm inventory-vm 'sudo pm2 list'" Enter
Sleep 4s
Type "vm billing-vm 'sudo pm2 list'" Enter
Sleep 4s
Type "vm gateway-vm 'sudo pm2 list'" Enter
Sleep 4s
Screenshot docs/media/01-vms-and-pm2.png
Sleep 1s
Type "clear" Enter

# --- 2. Inventory through the gateway
Type "# 2. Movies CRUD through the API Gateway (:3000 -> inventory-vm :8080)" Enter
Sleep 500ms
Type `api -X POST localhost:3000/api/movies -d '{"title":"Inception","description":"A dream heist"}'` Enter
Sleep 1500ms
Type `api -X POST localhost:3000/api/movies -d '{"title":"Interstellar","description":"Space and time"}'` Enter
Sleep 1500ms
Type "api 'localhost:3000/api/movies?title=incep'" Enter
Sleep 1500ms
Type `api -X PUT localhost:3000/api/movies/1 -d '{"description":"Updated description"}'` Enter
Sleep 1500ms
Type "api localhost:3000/api/movies/999" Enter
Sleep 1500ms
Screenshot docs/media/02-movies-via-gateway.png
Sleep 1s
Type "api -X DELETE localhost:3000/api/movies/2" Enter
Sleep 1500ms
Type "api localhost:3000/api/movies" Enter
Sleep 2s
Type "clear" Enter

# --- 3. Billing through RabbitMQ
Type "# 3. Billing: gateway publishes to billing_queue, billing-app stores the order" Enter
Sleep 500ms
Type `api -X POST localhost:3000/api/billing -d '{"user_id":"3","number_of_items":"5","total_amount":"180"}'` Enter
Sleep 1500ms
Type `api -X POST localhost:3000/api/billing -d '{"user_id":"3"}'` Enter
Sleep 1500ms
Type "orders" Enter
Sleep 4s
Screenshot docs/media/03-billing.png
Sleep 1s
Type "clear" Enter

# --- 4. Resilience
Type "# 4. Resilience: stop billing_app, orders still accepted and queued" Enter
Sleep 500ms
Type "vm billing-vm 'sudo pm2 stop billing_app'" Enter
Sleep 4s
Type `api -X POST localhost:3000/api/billing -d '{"user_id":"7","number_of_items":"1","total_amount":"15"}'` Enter
Sleep 1500ms
Type `api -X POST localhost:3000/api/billing -d '{"user_id":"9","number_of_items":"2","total_amount":"40"}'` Enter
Sleep 1500ms
Type "queue && orders" Enter
Sleep 7s
Screenshot docs/media/04-billing-stopped.png
Sleep 1s
Type "clear" Enter
Type "# restart billing_app: the pending messages are processed" Enter
Sleep 500ms
Type "vm billing-vm 'sudo pm2 start billing_app'" Enter
Sleep 6s
Type "queue && orders" Enter
Sleep 7s
Screenshot docs/media/05-billing-restarted.png
Sleep 1s
Type "clear" Enter

# --- 5. Postman collection
Type "# 5. Postman collection (Inventory + Gateway tests) with newman" Enter
Sleep 500ms
Type "npx -y newman run postman/crud-master.postman_collection.json" Enter
Sleep 25s
Screenshot docs/media/06-newman.png
Sleep 2s
