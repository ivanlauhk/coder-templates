terraform {
    required_providers {
        coder = {
            source = "coder/coder"
        }
        docker = {
            source = "kreuzwerker/docker"
        }
    }
}

locals {
    username = data.coder_workspace.me.owner
    image = {
        "Java"   = "codercom/enterprise-java:ubuntu"
        "Python" = "codercom/enterprise-base:ubuntu"
        "Go"     = "codercom/enterprise-golang:ubuntu"
        "Node"   = "codercom/enterprise-node:ubuntu"
    }
}

provider "docker" {}

provider "coder" {}

data "coder_provisioner" "me" {}

data "coder_workspace" "me" {}

module "vscode-web" {
  source         = "https://registry.coder.com/modules/vscode-web"
  agent_id       = coder_agent.main.id
  accept_license = true
  folder         = "/home/coder/project"
  install_dir    = "/tmp/vscode"
  log_path       = "/tmp/vscode.log"
}

module "jetbrains_gateway" {
    source         = "https://registry.coder.com/modules/jetbrains-gateway"
    agent_id       = coder_agent.main.id
    agent_name     = "main"
    folder         = "/home/coder/project"
    jetbrains_ides = ["IU", "WS", "PY", "GO"]
    default        = "IU"
}

module "vscode" {
  source = "https://registry.coder.com/modules/vscode-desktop"
  agent_id = coder_agent.main.id
  folder = "/home/coder/project"
}

module "dotfiles" {
  source   = "https://registry.coder.com/modules/dotfiles"
  agent_id = coder_agent.main.id
}

module "coder-login" {
    source   = "https://registry.coder.com/modules/coder-login"
    agent_id = coder_agent.main.id
}

data "coder_parameter" "lang" {
    name        = "Programming Language"
    type        = "string"
    description = "What container image and language do you want?"
    mutable     = true
    default     = "Node"
    icon        = "/icon/docker.png"

    option {
        name  = "Node"
        value = "Node"
        icon  = "/icon/node.svg"
    }
    option {
        name  = "Python"
        value = "Python"
        icon  = "/icon/python.svg"
    }
    option {
        name  = "Go"
        value = "Go"
        icon  = "/icon/go.svg"
    }
    option {
        name  = "Java"
        value = "Java"
        icon  = "/icon/java.svg"
    }
    order = 1
}

resource "coder_agent" "main" {
    os   = "linux"
    arch = data.coder_provisioner.me.arch

    env = {
        GIT_AUTHOR_NAME = data.coder_workspace.me.owner
        GIT_COMMITTER_NAME = data.coder_workspace.me.owner
        GIT_AUTHOR_EMAIL = data.coder_workspace.me.owner_email
        GIT_COMMITTER_EMAIL = data.coder_workspace.me.owner_email
    }

    metadata {
        display_name = "CPU Usage"
        key          = "0_cpu_usage"
        script       = "coder stat cpu"
        interval     = 10
        timeout      = 1
    }

    metadata {
        display_name = "RAM Usage"
        key          = "1_ram_usage"
        script       = "coder stat mem"
        interval     = 10
        timeout      = 1
    }

    metadata {
        display_name = "Home Disk"
        key          = "3_home_disk"
        script       = "coder stat disk --path $${HOME}"
        interval     = 60
        timeout      = 1
    }

    display_apps {
        vscode                 = false
        vscode_insiders        = false
        ssh_helper             = true
        port_forwarding_helper = true
        web_terminal           = true
    }

    dir                     = "/home/coder"
    startup_script_behavior = "blocking"
    startup_script_timeout  = 180
    startup_script          = <<EOT
        mkdir -p /home/coder/project
    EOT
}

resource "docker_container" "workspace" {
    count      = data.coder_workspace.me.start_count
    image      = "docker.io/${lookup(local.image, data.coder_parameter.lang.value)}"
    name       = "coder-${data.coder_workspace.me.owner}-${lower(data.coder_workspace.me.name)}"
    hostname   = lower(data.coder_workspace.me.name)
    dns        = ["1.1.1.1"]
    entrypoint = ["sh", "-c", "echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] http://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list && curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg && apt-get update -y && apt-get install google-cloud-sdk x11-apps -y &&  && ${replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")}"]
    env        = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]
    host {
        host = "host.docker.internal"
        ip   = "host-gateway"
    }
    volumes {
        container_path = "/home/coder"
        volume_name    = docker_volume.coder_volume.name
        read_only      = false
    }
    labels {
        label = "coder.owner"
        value = data.coder_workspace.me.owner
    }
    labels {
        label = "coder.owner_id"
        value = data.coder_workspace.me.owner_id
    }
    labels {
        label = "coder.workspace_id"
        value = data.coder_workspace.me.id
    }
    labels {
        label = "coder.workspace_name"
        value = data.coder_workspace.me.name
    }
}

resource "docker_volume" "coder_volume" {
    name = "coder-${data.coder_workspace.me.id}-home"
    # Protect the volume from being deleted due to changes in attributes.connection {
    lifecycle {
        ignore_changes = all
    }
}

resource "coder_metadata" "workspace_info" {
    count       = data.coder_workspace.me.start_count
    resource_id = docker_container.workspace[0].id
    item {
        key   = "dockerhub-image"
        value = "${lookup(local.image, data.coder_parameter.lang.value)}"
    }
    item {
        key   = "language"
        value = data.coder_parameter.lang.value
    }
}

