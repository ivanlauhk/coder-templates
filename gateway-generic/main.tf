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

provider "docker" {
}

provider "coder" {
}

data "coder_provisioner" "me" {
}

data "coder_workspace" "me" {
}

# module "code-server" {
#     source = "https://registry.coder.com/modules/code-server"
#     agent_id = coder_agent.main.id
# }

module "jetbrains_gateway" {
	source         = "https://registry.coder.com/modules/jetbrains-gateway"
	agent_id       = coder_agent.main.id
	agent_name     = "main"
	folder         = "/home/${local.username}"
	jetbrains_ides = ["IU", "WS", "PY", "GO"]
	default        = "IU"
}

module "jupyterlab" {
    source = "https://registry.coder.com/modules/jupyterlab"
    agent_id = coder_agent.main.id
}

module "dotfiles" {
  source = "https://registry.coder.com/modules/dotfiles"
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
		name = "Node"
		value = "Node"
		icon = "/icon/node.svg"
	}
	option {
		name = "Python"
		value = "Python"
		icon = "/icon/python.svg"
	}
	option {
		name = "Go"
		value = "Go"
		icon = "/icon/go.svg"
	} 
	option {
		name = "Java"
		value = "Java"
		icon = "/icon/java.svg"
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
		vscode = false
		vscode_insiders = false
		ssh_helper = true
		port_forwarding_helper = true
		web_terminal = true
	}

	dir = "/home/${local.username}"
	startup_script_behavior = "blocking"
	startup_script_timeout = 180
	startup_script = <<EOT
#!/bin/sh

# add github to known hosts
mkdir -p ~/.ssh
ssh-keyscan -t ed25519 github.com >> ~/.ssh/known_hosts

# install and start code-server
curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone
code-server --auth none --port 13337 >/dev/null 2>&1 &

	EOT
}

resource "coder_app" "code-server" {
	agent_id      = coder_agent.main.id
	slug          = "code-server"
	display_name  = "code-server"
	icon          = "/icon/code.svg"
	url           = "http://localhost:13337?folder=/home/${local.username}"
	subdomain     = true
	share         = "owner"
	healthcheck {
		url       = "http://localhost:13337/healthz"
		interval  = 3
		threshold = 10
	}  
}

resource "docker_container" "workspace" {
	count      = data.coder_workspace.me.start_count
	image      = "docker.io/${lookup(local.image, data.coder_parameter.lang.value)}"
	name       = "coder-${data.coder_workspace.me.owner}-${lower(data.coder_workspace.me.name)}"
	hostname   = lower(data.coder_workspace.me.name)
	dns        = ["1.1.1.1"]
	entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
	env        = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]
	host {
		host = "host.docker.internal"
		ip   = "host-gateway"
	}
	volumes {
		container_path = "/home/${local.username}"
		volume_name    = docker_volume.coder_volume.name
		read_only      = false
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