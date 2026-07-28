FROM archlinux AS base

# ==========================================
# ROOT CONTEXT: System Configuration
# ==========================================

# FIX: Added && \ to correctly chain commands and configure pacman
RUN echo "Configuring pacman" && \
	sed -i 's/^#Color/Color/g' /etc/pacman.conf && \
	sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 5/g' /etc/pacman.conf

# FIX: Added base-devel to support AUR package builds
RUN pacman -Syu --noconfirm && pacman -Fy --noconfirm
RUN pacman -S --noconfirm \
	base-devel bubblewrap \
	aspnet-targeting-pack aspnet-runtime aws-cli \
	bat btop \
	clang cmake curl \
	dnsutils dotnet-sdk \
	fakeroot fd fzf \
	gcc git git-delta \
	jq \
	less \
	make mono mono-msbuild \
	ncdu neovim nginx nuget \
	openssh \
	python-pip \
	ranger ripgrep \
	socat sshfs stow sudo \
	tmux tree-sitter-cli \
	tree \
	unzip upterm \
	vim \
	wget \
	xclip \
	yq \
	zip zoxide zsh

RUN echo "Configuring makepkg" && \
	sed -i 's/^PKGEXT.*/PKGEXT=".pkg.tar"/' /etc/makepkg.conf && \
	sed -i 's/\(OPTIONS=.*\)debug/\1!debug/' /etc/makepkg.conf

# FIX: Generate locale before setting ENV so Unicode works
RUN sed -i '/en_US.UTF-8/s/^#//g' /etc/locale.gen && \
	locale-gen
ENV LANG='en_US.UTF-8' LANGUAGE='en_US:en' LC_ALL='en_US.UTF-8'

# ==========================================
# USER CONTEXT: Dynamic UID/GID Mapping
# ==========================================

# These ARGs capture your host UID/GID during the build
ARG USER_UID=1000
ARG USER_GID=1000

# Create the dev group and user with the matching UID/GID
RUN groupadd --gid $USER_GID devgroup || true && \
	useradd --uid $USER_UID --gid $USER_GID -m -G wheel -s /bin/zsh dev && \
	passwd -d dev && \
	echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel

# Setup root-level mount point and give the dev user ownership
RUN mkdir -p /mnt/c/Projects.Git && \
	chown -R dev:devgroup /mnt/c/Projects.Git

# Switch all future commands to run as the non-root 'dev' user
USER dev
ENV USER=dev
WORKDIR /home/dev

# ==========================================
# DEV USER CONTEXT: Environment Setup
# ==========================================

ARG GIT_EMAIL
ARG GIT_NAME

# Note: Escaped variables like \$LOCAL so Docker doesn't evaluate them at build time
RUN echo -e "\033[32m Configure Git\033[0m" && \
	git config --global user.email "$GIT_EMAIL" && \
	git config --global user.name "$GIT_NAME" && \
	git config --global alias.logo "log --pretty=tformat:'%C(auto,red)%m %C(auto,yellow)%h%C(auto,magenta) %G? %C(auto,blue)%>(12,trunc)%ad %C(auto,green)%<(15,trunc)%aN%C(auto,reset)%s%C(auto,red) %gD %D' --date=short" && \
	git config --global alias.adog "log --all --decorate --oneline --graph" && \
	git config --global alias.dog "log --decorate --oneline --graph" && \
	git config --global pull.rebase true && \
	git config --global submodule.recurse true && \
	git config --global core.editor "nvim" && \
	git config --global core.excludesfile ~/.gitignore && \
	git config --global core.autocrlf input && \
	git config --global init.defaultBranch master && \
	git config --global rerere.enabled true && \
	git config --global merge.tool nvim && \
	git config --global merge.conflictstyle diff3 && \
	git config --global mergetool.nvim.cmd "nvim -d \$LOCAL \$BASE \$REMOTE \$MERGED -c '\$wincmd w' -c 'wincmd J'" && \
	git config --global gpg.ssh.allowedSignersFile /home/dev/.ssh/allowed_signers

RUN echo -e "\033[32m Clone KiLLeRRaT dotfiles\033[0m" && \
	git clone https://github.com/KiLLeRRaT/.dotfiles /home/dev/.dotfiles

WORKDIR /home/dev/.dotfiles
RUN echo -e "\033[32m Run Stow\033[0m" && \
	rm -f /home/dev/.bashrc /home/dev/.bash_profile /home/dev/.bash_logout /home/dev/.zshrc && \
	stow bashrc && \
	stow fonts && \
	stow nvim-lua && \
	stow oh-my-posh && \
	stow ranger && \
	stow ssh && \
	chmod 700 /home/dev/.dotfiles/ssh/.ssh && \
	chmod 600 /home/dev/.dotfiles/ssh/.ssh/id_* /home/dev/.dotfiles/ssh/.ssh/config 2>/dev/null || true && \
	stow tmux && \
	stow zshrc


# Reset WORKDIR to home for AUR builds
# WORKDIR /home/dev
# # FIX: Run makepkg natively as 'dev' without sudo workarounds
# RUN echo -e "\033[32m Install oh-my-posh\033[0m" && \
#	git clone https://aur.archlinux.org/oh-my-posh.git oh-my-posh-aur && \
#	cd oh-my-posh-aur && makepkg -is --noconfirm
# RUN echo -e "\033[32m Install NVM\033[0m" && \
#	git clone https://aur.archlinux.org/nvm.git nvm-aur && \
#	cd nvm-aur && makepkg -is --noconfirm
# RUN echo -e "\033[32m Install Claude Code\033[0m" && \
#	git clone https://aur.archlinux.org/claude-code.git claude-code-aur && \
#	cd claude-code-aur && makepkg -is --noconfirm

# Reset WORKDIR to home for AUR builds
WORKDIR /home/dev

# ==========================================
# AUR Packages
# ==========================================
RUN echo -e "\033[32m Install Yay\033[0m" && \
	git clone https://aur.archlinux.org/yay-bin.git /home/dev/yay-bin && \
	cd /home/dev/yay-bin && \
	makepkg -is --noconfirm && \
	rm -rf /home/dev/yay-bin

RUN echo -e "\033[32m Install AUR Packages\033[0m" && \
	yay -S --noconfirm oh-my-posh nvm claude-code


RUN echo -e "\033[32m Clone zsh-vi-mode\033[0m" && \
	git clone https://github.com/jeffreytse/zsh-vi-mode.git /home/dev/.zsh-vi-mode

RUN echo -e "\033[32m Nuget credential provider for .NET Core Azure DevOps\033[0m" && \
	wget -qO- https://aka.ms/install-artifacts-credprovider.sh | bash

RUN echo -e "\033[32m Nuget credential provider for .NET Framework Azure DevOps\033[0m" && \
	mkdir -p /home/dev/.nuget/plugins/netfx && \
	if ! curl -H "Accept: application/octet-stream" -s -S -L "https://github.com/microsoft/artifacts-credprovider/releases/download/v1.0.0/Microsoft.NuGet.CredentialProvider.tar.gz" | tar xz -C "/home/dev/.nuget/" "plugins/netfx"; then exit 1 ; fi

RUN echo -e "\033[32m Make norg dummy directories\033[0m" && \
	mkdir -p /home/dev/notes/neorg/work && \
	touch /home/dev/notes/neorg/work/inbox.norg && \
	touch /home/dev/notes/neorg/work/index.norg && \
	mkdir -p /home/dev/source


# ==========================================
# FULLY BAKE PLUGINS & NODE
# ==========================================

# Temporarily switch Docker's default shell to zsh so we can source your config
SHELL ["/bin/zsh", "-c"]

RUN echo -e "\033[32mInstalling node using nvm...\033[0m" && \
	source ~/.zshrc && \
	nvm install --lts && \
	nvm use --lts && \
	node --version

RUN echo -e "\033[32mRunning nvim to install plugins...\033[0m" && \
	source ~/.zshrc && \
	nvim --headless +Lazy! +qa

RUN echo -e "\033[32mBuilding telescope-fzf-native...\033[0m" && \
	cd ~/.local/share/nvim/lazy/telescope-fzf-native.nvim && \
	make

RUN echo -e "\033[32mRunning nvim again to install TreeSitter parsers\033[0m" && \
	source ~/.zshrc && \
	nvim --headless +qa



# CONFIGURE NPMRC
RUN cat <<'EOF' > ~/.npmrc
//pkgs.dev.azure.com/sandfield/_packaging/Sandfield.NPM/npm/registry/:username=sandfield
//pkgs.dev.azure.com/sandfield/_packaging/Sandfield.NPM/npm/registry/:_password=${NPM_AUTH_TOKEN}
//pkgs.dev.azure.com/sandfield/_packaging/Sandfield.NPM/npm/registry/:email=npm requires email to be set but doesn't use the value
//pkgs.dev.azure.com/sandfield/_packaging/Sandfield.NPM/npm/:username=sandfield
//pkgs.dev.azure.com/sandfield/_packaging/Sandfield.NPM/npm/:_password=${NPM_AUTH_TOKEN}
//pkgs.dev.azure.com/sandfield/_packaging/Sandfield.NPM/npm/:email=npm requires email to be set but doesn't use the value
//sandfield.pkgs.visualstudio.com/_packaging/Sandfield.NPM/npm/registry/:username=sandfield
//sandfield.pkgs.visualstudio.com/_packaging/Sandfield.NPM/npm/registry/:_password=${NPM_AUTH_TOKEN}
//sandfield.pkgs.visualstudio.com/_packaging/Sandfield.NPM/npm/registry/:email=npm requires email to be set but doesn't use the value
//sandfield.pkgs.visualstudio.com/_packaging/Sandfield.NPM/npm/:username=sandfield
//sandfield.pkgs.visualstudio.com/_packaging/Sandfield.NPM/npm/:_password=${NPM_AUTH_TOKEN}
//sandfield.pkgs.visualstudio.com/_packaging/Sandfield.NPM/npm/:email=npm requires email to be set but doesn't use the value
//pkgs.dev.azure.com/sandfield/_packaging/Sandfield.NPMTest/npm/registry/:username=sandfield
//pkgs.dev.azure.com/sandfield/_packaging/Sandfield.NPMTest/npm/registry/:_password=${NPM_AUTH_TOKEN}
//pkgs.dev.azure.com/sandfield/_packaging/Sandfield.NPMTest/npm/registry/:email=npm requires email to be set but doesn't use the value
//pkgs.dev.azure.com/sandfield/_packaging/Sandfield.NPMTest/npm/:username=sandfield
//pkgs.dev.azure.com/sandfield/_packaging/Sandfield.NPMTest/npm/:_password=${NPM_AUTH_TOKEN}
//pkgs.dev.azure.com/sandfield/_packaging/Sandfield.NPMTest/npm/:email=npm requires email to be set but doesn't use the value
registry=https://registry.npmjs.org/
EOF


# Revert back to standard sh just to be safe for any future commands
SHELL ["/bin/sh", "-c"]

# Avoid container exit.
CMD ["tail", "-f", "/dev/null"]

