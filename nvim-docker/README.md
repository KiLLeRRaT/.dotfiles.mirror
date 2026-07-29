# Building the image

First-run sequence: build the image, then verify that the container actually came
up correctly. Create your `.env` from `.env.example` first - every wrapper script
below reads it, and `docker-run.sh` refuses to start without it.

The commented lines are the expected results - check each one as you go.

One-time migration note (only if you used the old raw `docker run`): if you
previously started this container with `docker run` rather than the compose
wrapper scripts, you have an orphaned container that compose does not manage.
`docker compose down` will not remove it, and `docker compose up` fails with the
name `nvim-docker` already in use. Remove it once, before the sequence below:

```
sudo docker rm -f nvim-docker
```

Then:

```
cp .env.example .env    # then edit it for this machine
```

```
./docker-build.sh                        # n / n  (--no-cache? then push?)
sudo docker images | grep nvim-docker    # :latest AND the git-SHA tag
./docker-run.sh                          # expect "X11: enabled (DISPLAY=…)"
./docker-exec.sh
  ssh-add -l          # 1Password keys, not "error connecting"
  echo $NPM_AUTH_TOKEN ; echo $IN_DOCKER ; echo $TZ
  echo hi | xclip -selection clipboard && xclip -o -selection clipboard
  touch /home/dev/notes/x   # MUST fail (ro)
  exit
./docker-stop-and-remove.sh && env -u DISPLAY ./docker-run.sh
sudo docker exec nvim-docker env | grep -c DISPLAY    # must be 0 — unset, not set-and-broken
```

To create and run the container:
# Linux or MacOS
```
sudo docker run -d --name nvim-docker -v /mnt/c/Projects.Git:/mnt/c/Projects.Git killerrat/nvim-docker:latest
```
# Windows
```
docker run -d --name nvim-docker -v C:\Projects.Git:/mnt/c/Projects.Git killerrat/nvim-docker:latest
```


# To get into the container
```
docker exec -it nvim-docker /bin/zsh
```
Then start tmux, with unicode otherwise characters display funny:
```
tmux -u # THIS WAS REMOVED AT SOME POINT, NOT SURE WHY I DID THAT...
tmux
```

This image also comes with [upterm](https://github.com/owenthereal/upterm), which lets you host a shared SSH session without having to open special firewall ports and such:
```
upterm host zsh
```
Or forcing a tmux session:
```
upterm host --force-command 'tmuxu attach -t pair-programming' -- tmux new -t pair-programming
```

# Nuget Package Source
```
dotnet nuget add source https://pkgs.dev.azure.com/sandfield/_packaging/Sandfield.Nuget/nuget/v3/index.json --name Sandfield.Nuget
```

To install a package (basically to authenticate):
```
dotnet add package Sandfield.Data.Dynamic --interactive
```
