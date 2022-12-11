FROM ubuntu

# update APT
RUN apt-get update
# install basic
RUN apt-get install -y curl git golang sudo nano wget htop gzip zip unzip
# install nodejs
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
RUN apt-get install -y nodejs
# install python3
RUN apt-get install -y python3
# clear APT cache
RUN rm -rf /var/lib/apt/lists/*

ARG USER=coder
RUN useradd --groups sudo --no-create-home ${USER} \
&& echo "${USER} ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/${USER} \
&& chmod 0440 /etc/sudoers.d/${USER}
USER ${USER}
WORKDIR /home/${USER}

RUN chsh -s /bin/bash
ENV SHELL=/bin/bash