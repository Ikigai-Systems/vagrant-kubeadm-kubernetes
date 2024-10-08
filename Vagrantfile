
require "yaml"
vagrant_root = File.dirname(File.expand_path(__FILE__))
settings = YAML.load_file "#{vagrant_root}/settings.yaml"
autostart = settings["autostart"]

IP_SECTIONS = settings["network"]["control_ip"].match(/^([0-9.]+\.)([^.]+)$/)
# First 3 octets including the trailing dot:
IP_NW = IP_SECTIONS.captures[0]
# Last octet excluding all dots:
IP_START = Integer(IP_SECTIONS.captures[1])
NUM_WORKER_NODES = settings["nodes"]["workers"]["count"]

Vagrant.configure("2") do |config|
  config.vm.synced_folder "./", "/vagrant", type: "nfs", nfs_version: 4

  config.vm.provider "libvirt" do |libvirt|
      libvirt.uri = "qemu:///system"
      libvirt.driver = "qemu"
      libvirt.management_network_autostart = autostart
      libvirt.autostart = autostart
  end

  config.vm.provision "shell", env: { "IP_NW" => IP_NW, "IP_START" => IP_START, "NUM_WORKER_NODES" => NUM_WORKER_NODES }, inline: <<-SHELL
      apt-get update -y
      echo "$IP_NW$((IP_START)) controlplane" >> /etc/hosts
      for i in `seq 1 ${NUM_WORKER_NODES}`; do
        echo "$IP_NW$((IP_START+i)) node0${i}" >> /etc/hosts
      done
  SHELL

  if `uname -m`.strip == "aarch64"
    config.vm.box = settings["software"]["box"] + "-arm64"
  else
    config.vm.box = settings["software"]["box"]
  end
  config.vm.box_check_update = true

  config.vm.define "controlplane" do |controlplane|
    controlplane.vm.hostname = "controlplane"
    controlplane.vm.network "private_network", ip: settings["network"]["control_ip"], autostart: autostart

    if settings["shared_folders"]
      settings["shared_folders"].each do |shared_folder|
        controlplane.vm.synced_folder shared_folder["host_path"], shared_folder["vm_path"]
      end
    end

    controlplane.vm.provider "virtualbox" do |vb|
        vb.cpus = settings["nodes"]["control"]["cpu"]
        vb.memory = settings["nodes"]["control"]["memory"]

        if settings["cluster_name"] and settings["cluster_name"] != ""
          vb.customize ["modifyvm", :id, "--groups", ("/" + settings["cluster_name"])]
        end

        if autostart
          vb.customize ["modifyvm", :id, "--autostart-enabled", "on"]
          vb.customize ["modifyvm", :id, "--autostop-type", "acpishutdown"]
        end
    end

    controlplane.vm.provider "libvirt" do |vb|
        vb.cpus = settings["nodes"]["control"]["cpu"]
        vb.memory = settings["nodes"]["control"]["memory"]
    end

    controlplane.vm.provision "shell",
      env: {
        "DNS_SERVERS" => settings["network"]["dns_servers"].join(" "),
        "ENVIRONMENT" => settings["environment"],
        "KUBERNETES_VERSION" => settings["software"]["kubernetes"],
        "KUBERNETES_VERSION_SHORT" => settings["software"]["kubernetes"][0..3],
        "OS" => settings["software"]["os"],
        "CRI" => settings["software"]["cri"],
        "CRI_VERSION" => settings["software"]["cri-version"],
        "CRI_VERSION_SHORT" => settings["software"]["cri-version"][0..3],
      },
      path: "scripts/common.sh"

    controlplane.vm.provision "shell",
      env: {
        "CALICO_VERSION" => settings["software"]["calico"],
        "CONTROL_IP" => settings["network"]["control_ip"],
        "POD_CIDR" => settings["network"]["pod_cidr"],
        "SERVICE_CIDR" => settings["network"]["service_cidr"]
      },
      path: "scripts/master.sh"
  end

  (1..NUM_WORKER_NODES).each do |i|

    config.vm.define "node0#{i}" do |node|
      node.vm.hostname = "node0#{i}"
      node.vm.network "private_network", ip: IP_NW + "#{IP_START + i}", autostart: autostart

      if settings["shared_folders"]
        settings["shared_folders"].each do |shared_folder|
          node.vm.synced_folder shared_folder["host_path"], shared_folder["vm_path"]
        end
      end

      node.vm.provider "virtualbox" do |vb|
          vb.cpus = settings["nodes"]["workers"]["cpu"]
          vb.memory = settings["nodes"]["workers"]["memory"]

          if settings["cluster_name"] and settings["cluster_name"] != ""
            vb.customize ["modifyvm", :id, "--groups", ("/" + settings["cluster_name"])]
          end

          if autostart
            vb.customize ["modifyvm", :id, "--autostart-enabled", "on"]
            vb.customize ["modifyvm", :id, "--autostop-type", "acpishutdown"]
          end
      end

      node.vm.provider "libvirt" do |vb|
          vb.cpus = settings["nodes"]["workers"]["cpu"]
          vb.memory = settings["nodes"]["workers"]["memory"]
      end

      node.vm.provision "shell",
        env: {
          "DNS_SERVERS" => settings["network"]["dns_servers"].join(" "),
          "ENVIRONMENT" => settings["environment"],
          "KUBERNETES_VERSION" => settings["software"]["kubernetes"],
          "KUBERNETES_VERSION_SHORT" => settings["software"]["kubernetes"][0..3],
          "OS" => settings["software"]["os"],
          "CRI" => settings["software"]["cri"],
          "CRI_VERSION" => settings["software"]["cri-version"],
          "CRI_VERSION_SHORT" => settings["software"]["cri-version"][0..3],
        },
        path: "scripts/common.sh"

      node.vm.provision "shell", path: "scripts/node.sh"

      if File.exist?("scripts/customize-node.sh")
        node.vm.provision "shell", path: "scripts/customize-node.sh"
      end

      # Only install the dashboard after provisioning the last worker (and when enabled).
      if i == NUM_WORKER_NODES and settings["software"]["dashboard"] and settings["software"]["dashboard"] != ""
        node.vm.provision "shell", path: "scripts/dashboard.sh"
      end
    end

  end
end 
