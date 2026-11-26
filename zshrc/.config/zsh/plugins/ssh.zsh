ssh-remove-and-connect(){
	# $1 is in the form of username@hostname
	username=$(cut -d'@' -f1 <<< $1)
	hostname=$(cut -d'@' -f2 <<< $1)
	sed -i.bak "/^$hostname /d" ~/.ssh/known_hosts
	# ssh $username@$hostname
	ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no -o PasswordAuthentication=yes $username@$hostname
}

ssh-with-password(){
	username=$(cut -d'@' -f1 <<< $1)
	hostname=$(cut -d'@' -f2 <<< $1)
	ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no -o PasswordAuthentication=yes $username@$hostname
}

# Gitignored work SSH hosts (~/.ssh/config.d/sandfield), kept in 1Password as a Document.
# Pulled in by `Include config.d/*` at the top of ~/.ssh/config.
SSH_SANDFIELD_DOC="SSH Config - Sandfield"
SSH_SANDFIELD_VAULT="Gouws.org Computers"
SSH_SANDFIELD_FILE=~/.ssh/config.d/sandfield

# Fetch the file from 1Password (new machine, or after editing it elsewhere).
ssh-sandfield-pull(){
	mkdir -p ~/.ssh/config.d
	op --account my.1password.com document get "$SSH_SANDFIELD_DOC" \
		--vault "$SSH_SANDFIELD_VAULT" \
		--out-file "$SSH_SANDFIELD_FILE" --force \
		&& chmod 600 "$SSH_SANDFIELD_FILE"
}

# Upload local edits. Creates the 1Password Document the first time.
ssh-sandfield-push(){
	if op --account my.1password.com document get "$SSH_SANDFIELD_DOC" \
		--vault "$SSH_SANDFIELD_VAULT" >/dev/null 2>&1; then
		op --account my.1password.com document edit "$SSH_SANDFIELD_DOC" \
			--vault "$SSH_SANDFIELD_VAULT" "$SSH_SANDFIELD_FILE"
	else
		op --account my.1password.com document create "$SSH_SANDFIELD_FILE" \
			--vault "$SSH_SANDFIELD_VAULT" --title "$SSH_SANDFIELD_DOC"
	fi
}

