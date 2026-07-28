# -*- mode: ruby -*-
# vi: set ft=ruby :

# Load .env into ENV so both Vagrant and the provisioning scripts see the
# same values (per project requirement: no credentials hardcoded anywhere).
env_file = File.join(File.dirname(__FILE__), ".env")
if File.exist?(env_file)
  File.readlines(env_file).each do |line|
    line = line.strip
    next if line.empty? || line.start_with?("#")
    key, value = line.split("=", 2)
    ENV[key] = value if key && value
  end
end

INVENTORY_IP = "192.168.56.11"
BILLING_IP   = "192.168.56.12"
GATEWAY_IP   = "192.168.56.13"

Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/jammy64"

  config.vm.provider "virtualbox" do |vb|
    vb.memory = 1024
    vb.cpus = 1
  end

  config.vm.provision "shell", path: "scripts/common.sh"

  config.vm.define "inventory-vm" do |inventory|
    inventory.vm.hostname = "inventory-vm"
    inventory.vm.network "private_network", ip: INVENTORY_IP
    inventory.vm.provision "shell", path: "scripts/inventory-vm.sh", env: {
      "INVENTORY_DB_NAME"     => ENV["INVENTORY_DB_NAME"],
      "INVENTORY_DB_USER"     => ENV["INVENTORY_DB_USER"],
      "INVENTORY_DB_PASSWORD" => ENV["INVENTORY_DB_PASSWORD"],
      "INVENTORY_DB_PORT"     => ENV["INVENTORY_DB_PORT"],
      "INVENTORY_APP_HOST"    => "0.0.0.0",
      "INVENTORY_APP_PORT"    => ENV["INVENTORY_APP_PORT"],
      "INVENTORY_DB_HOST"     => "localhost",
    }
  end

  config.vm.define "billing-vm" do |billing|
    billing.vm.hostname = "billing-vm"
    billing.vm.network "private_network", ip: BILLING_IP
    billing.vm.provision "shell", path: "scripts/billing-vm.sh", env: {
      "BILLING_DB_NAME"     => ENV["BILLING_DB_NAME"],
      "BILLING_DB_USER"     => ENV["BILLING_DB_USER"],
      "BILLING_DB_PASSWORD" => ENV["BILLING_DB_PASSWORD"],
      "BILLING_DB_PORT"     => ENV["BILLING_DB_PORT"],
      "BILLING_DB_HOST"     => "localhost",
      "RABBITMQ_USER"       => ENV["RABBITMQ_USER"],
      "RABBITMQ_PASSWORD"   => ENV["RABBITMQ_PASSWORD"],
      "RABBITMQ_PORT"       => ENV["RABBITMQ_PORT"],
      "RABBITMQ_HOST"       => "localhost",
      "BILLING_QUEUE"       => ENV["BILLING_QUEUE"],
    }
  end

  config.vm.define "gateway-vm" do |gateway|
    gateway.vm.hostname = "gateway-vm"
    gateway.vm.network "private_network", ip: GATEWAY_IP
    gateway.vm.provision "shell", path: "scripts/gateway-vm.sh", env: {
      "GATEWAY_APP_HOST"  => "0.0.0.0",
      "GATEWAY_APP_PORT"  => ENV["GATEWAY_APP_PORT"],
      "INVENTORY_API_URL" => "http://#{INVENTORY_IP}:#{ENV["INVENTORY_APP_PORT"]}",
      "RABBITMQ_HOST"     => BILLING_IP,
      "RABBITMQ_PORT"     => ENV["RABBITMQ_PORT"],
      "RABBITMQ_USER"     => ENV["RABBITMQ_USER"],
      "RABBITMQ_PASSWORD" => ENV["RABBITMQ_PASSWORD"],
      "BILLING_QUEUE"     => ENV["BILLING_QUEUE"],
    }
  end
end
