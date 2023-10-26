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

module "jetbrains_gateway" {
	source         = "https://registry.coder.com/modules/jetbrains-gateway"
	agent_id       = coder_agent.dev.id
	agent_name     = "dev"
	folder         = "/home/${local.username}"
	jetbrains_ides = ["GO", "WS", "IU", "PY"]
	default        = "IU"
}

data "coder_parameter" "lang" {
	name        = "Programming Language"
	type        = "string"
	description = "What container image and language do you want?"
	mutable     = true
	default     = "Node"
	icon        = "https://www.docker.com/wp-content/uploads/2022/03/vertical-logo-monochromatic.png"

	option {
		name = "Node"
		value = "Node"
		icon = "https://cdn.freebiesupply.com/logos/large/2x/nodejs-icon-logo-png-transparent.png"
	}
	option {
		name = "Python"
		value = "Python"
		icon = "https://upload.wikimedia.org/wikipedia/commons/thumb/c/c3/Python-logo-notext.svg/1869px-Python-logo-notext.svg.png"
	}
	option {
		name = "Go"
		value = "Go"
		icon = "https://upload.wikimedia.org/wikipedia/commons/thumb/0/05/Go_Logo_Blue.svg/1200px-Go_Logo_Blue.svg.png"
	} 
	option {
		name = "Java"
		value = "Java"
		icon = "https://assets.stickpng.com/images/58480979cef1014c0b5e4901.png"
	}
	order = 1       
}

data "coder_parameter" "dotfiles_url" {
	name        = "Dotfiles URL (optional)"
	description = "Personalize your workspace e.g., https://github.com/sharkymark/dotfiles.git"
	type        = "string"
	default     = ""
	mutable     = true 
	icon        = "https://git-scm.com/images/logos/downloads/Git-Icon-1788C.png"
	order       = 2
}

resource "coder_agent" "main" {
	os   = "linux"
	arch = data.coder_provisioner.me.arch

	env = {
		GIT_AUTHOR_NAME = data.coder_workspace.me.owner
		GIT_COMMITTER_NAME = data.coder_workspace.me.owner
		GIT_AUTHOR_EMAIL = data.coder_workspace.me.owner_email
		GIT_COMMITTER_EMAIL = data.coder_workspace.me.owner_email
		DOTFILES_URI = data.coder_parameter.dotfiles_url.value != "" ? data.coder_parameter.dotfiles_url.value : null
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

# use coder CLI to clone and install dotfiles
if [ -n "$DOTFILES_URI" ]; then
	echo "Installing dotfiles from $DOTFILES_URI"
	coder dotfiles -y "$DOTFILES_URI"
fi

# install and start code-server
curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone
code-server --auth none --port 13337 >/dev/null 2>&1 &

	EOT
}

# code-server
resource "coder_app" "code-server" {
	agent_id      = coder_agent.main.id
	slug          = "code-server"
	display_name  = "code-server"
	icon          = "/icon/code.svg"
	url           = "http://localhost:13337?folder=/home/${local.username}"
	subdomain     = false
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

# resource "docker_image" "main" {
#	name = "coder-${data.coder_workspace.me.id}"
#	build {
#		context = "./build"
#		build_args = {
#			USER = local.username
#		}
#	}
#	triggers = {
#    	dir_sha1 = sha1(join("", [for f in fileset(path.module, "build/*") : filesha1(f)]))
# 	}
#}

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

# test