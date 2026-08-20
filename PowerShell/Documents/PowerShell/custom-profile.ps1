# Portable: every external tool/module is guarded so this loads anywhere.

# posh-git: needs the git binary at import.
if ((Get-Command git -ErrorAction SilentlyContinue) -and (Get-Module -ListAvailable -Name posh-git)) {
  Import-Module posh-git
}

# PSFzf: Import-Module THROWS if the fzf binary isn't on PATH.
if ((Get-Command fzf -ErrorAction SilentlyContinue) -and (Get-Module -ListAvailable -Name PSFzf)) {
  Import-Module PSFzf
}

# OSC7 for oh-my-posh, see: https://github.com/JanDeDobbeleer/oh-my-posh/issues/2515#issuecomment-1374322136
function Set-EnvVar {
  $loc = $executionContext.SessionState.Path.CurrentLocation;

  $out = ""
  if ($loc.Provider.Name -eq "FileSystem") {
    $out += "$([char]27)]9;9;`"$($loc.ProviderPath)`"$([char]27)\"
  }
	$env:OSC7 = $out
}

$ompTheme = "$HOME/.omp/themes/tokyonight.omp.yaml"
if ((Get-Command oh-my-posh -ErrorAction SilentlyContinue) -and (Test-Path $ompTheme)) {
  New-Alias -Name 'Set-PoshContext' -Value 'Set-EnvVar' -Scope Global -Force
  oh-my-posh init pwsh --config $ompTheme | Invoke-Expression
}

if (Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue) {
  Set-PSReadlineOption -EditMode vi

  # zsh-style menu completion (like `menu select`): Tab completes the common prefix
  # then shows an interactive menu. fzf fuzzy match is on Ctrl+t (zsh's `**<TAB>`).
  Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
  Set-PSReadLineOption -ShowToolTips
  Set-PSReadLineKeyHandler -Key Ctrl+r -Function ReverseSearchHistory

  if (Get-Command Invoke-FzfTabCompletion -ErrorAction SilentlyContinue) {
    Set-PSReadLineKeyHandler -Key Ctrl+t -ScriptBlock { Invoke-FzfTabCompletion }
  }
}

# Remove gl/gp/gm so our git.bat helpers win (only if present, else errors).
foreach ($a in 'gl', 'gp', 'gm') {
  if (Get-Alias $a -ErrorAction SilentlyContinue) { Remove-Alias -Force -Name $a }
}

function n { nvim ${Args} }
function gs { git status ${Args} }
function gf { git fetch ${Args} }
function gu { git pull ${Args} }
function gp { git push ${Args} }
function gpt { git push --tags ${Args} }
function gP { git push --force-with-lease ${Args} }
function ga { git add ${Args} }
function gcam { git commit -am ${Args} }
function gd { git diff ${Args} }
function gw { git diff --word-diff ${Args} }
function gl { git logo ${Args} }
function gdog { git dog ${Args} }
function gadog { git adog ${Args} }
function gb { git branch ${Args} }
function gba { git branch --all ${Args} }
function gco { git checkout ${Args} }
function gm { git merge ${Args} }
function gr { git rebase ${Args} }
function gcd { Set-Location $(git rev-parse --show-toplevel) }

# zoxide v0.8.0+
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
  Invoke-Expression (& {
      $hook = if ($PSVersionTable.PSVersion.Major -lt 6) { 'prompt' } else { 'pwd' }
      (zoxide init --hook $hook powershell | Out-String)
  })
}
