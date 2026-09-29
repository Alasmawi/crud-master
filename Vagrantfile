# -*- mode: ruby -*-
# vi: set ft=ruby :

# Everything comes from .env: no credentials or addresses are defined here.
env_file = File.join(__dir__, ".env")
abort "Missing .env at #{env_file}" unless File.exist?(env_file)

ENV_VARS = {}
File.readlines(env_file).each do |line|
  line = line.strip
  next if line.empty? || line.start_with?("#")
  key, value = line.split("=", 2)
  ENV_VARS[key] = value.to_s.delete_prefix('"').delete_suffix('"') if key
end

def env_subset(*keys)
  keys.to_h { |k| [k, ENV_VARS.fetch(k)] }
end

Vagrant.configure("2") do |config|
  config.vm.box = ENV_VARS.fetch("VAGRANT_BOX")

  config.vm.provider "virtualbox" do |vb|
    vb.memory = 1024
    vb.cpus = 1
  end

  config.vm.provision "shell", path: "scripts/common.sh"

  config.vm.define "inventory-vm" do |inventory|
    inventory.vm.hostname = "inventory-vm"
    inventory.vm.network "private_network", ip: ENV_VARS.fetch("INVENTORY_VM_IP")
    inventory.vm.network "forwarded_port", guest: ENV_VARS.fetch("INVENTORY_APP_PORT").to_i, host: ENV_VARS.fetch("INVENTORY_APP_PORT").to_i
    inventory.vm.provision "shell", path: "scripts/inventory-vm.sh", env: env_subset(
      "INVENTORY_DB_HOST", "INVENTORY_DB_PORT", "INVENTORY_DB_NAME",
      "INVENTORY_DB_USER", "INVENTORY_DB_PASSWORD",
      "INVENTORY_APP_HOST", "INVENTORY_APP_PORT",
    )
  end

  config.vm.define "billing-vm" do |billing|
    billing.vm.hostname = "billing-vm"
    billing.vm.network "private_network", ip: ENV_VARS.fetch("BILLING_VM_IP")
    billing.vm.network "forwarded_port", guest: 15672, host: ENV_VARS.fetch("RABBITMQ_MANAGEMENT_PORT").to_i # RabbitMQ UI
    billing.vm.provider "virtualbox" do |vb|
      vb.memory = 2048 # PostgreSQL + RabbitMQ + billing-app
    end
    billing.vm.provision "shell", path: "scripts/billing-vm.sh", env: env_subset(
      "BILLING_DB_HOST", "BILLING_DB_PORT", "BILLING_DB_NAME",
      "BILLING_DB_USER", "BILLING_DB_PASSWORD",
      "RABBITMQ_HOST", "RABBITMQ_PORT", "RABBITMQ_USER", "RABBITMQ_PASSWORD",
      "BILLING_QUEUE",
    )
  end

  config.vm.define "gateway-vm" do |gateway|
    gateway.vm.hostname = "gateway-vm"
    gateway.vm.network "private_network", ip: ENV_VARS.fetch("GATEWAY_VM_IP")
    gateway.vm.network "forwarded_port", guest: ENV_VARS.fetch("GATEWAY_APP_PORT").to_i, host: ENV_VARS.fetch("GATEWAY_APP_PORT").to_i
    gateway.vm.provision "shell", path: "scripts/gateway-vm.sh", env: env_subset(
      "GATEWAY_APP_HOST", "GATEWAY_APP_PORT",
      "RABBITMQ_PORT", "RABBITMQ_USER", "RABBITMQ_PASSWORD", "BILLING_QUEUE",
    ).merge(
      # The gateway reaches the other two VMs over the private network.
      "INVENTORY_API_URL" => "http://#{ENV_VARS.fetch("INVENTORY_VM_IP")}:#{ENV_VARS.fetch("INVENTORY_APP_PORT")}",
      "RABBITMQ_HOST"     => ENV_VARS.fetch("BILLING_VM_IP"),
    )
  end
end
