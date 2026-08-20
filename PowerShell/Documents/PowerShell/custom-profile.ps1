# THIS IS NEEDED FOR GIT TAB COMPLETION
Import-Module posh-git

# PSFzf provides Invoke-FzfTabCompletion (bound to Ctrl+t below). Guarded so the
# profile doesn't error on machines where the module isn't installed
# (install with: Install-Module PSFzf -Scope CurrentUser).
if (Get-Module -ListAvailable -Name PSFzf) {
  Import-Module PSFzf
}

# IDEA FROM: https://github.com/JanDeDobbeleer/oh-my-posh/issues/2515#issuecomment-1374322136
# then remove the "pwd": "osc7" from the omp.json and add the following as the first element in the segments field.
# {
# 	"type": "text",
# 	"style": "plain",
# 	"template": "{{ .Env.OSC7 }}"
# },
function Set-EnvVar {
  $loc = $executionContext.SessionState.Path.CurrentLocation;

  $out = ""
  if ($loc.Provider.Name -eq "FileSystem") {
    $out += "$([char]27)]9;9;`"$($loc.ProviderPath)`"$([char]27)\"
  }
	$env:OSC7 = $out
}
New-Alias -Name 'Set-PoshContext' -Value 'Set-EnvVar' -Scope Global -Force
oh-my-posh init pwsh --config ~/.omp/themes/tokyonight.omp.yaml | Invoke-Expression

# $Host.UI.RawUI.WindowTitle = "$pwd"


# PSReadLine extension to provide VI keybindings
Set-PSReadlineOption -EditMode vi
# Set-PSReadLineKeyHandler -Key j,k -Function ViCommandMode

# Zsh-style completion (mirrors `zstyle ':completion:*' menu select` in .zshrc).
# MenuComplete completes to the longest common prefix, then shows an INTERACTIVE
# menu of matches below the prompt that you navigate with the arrow keys / Tab
# (Shift+Tab navigates backwards within the menu automatically) and accept with
# Enter -- instead of PowerShell's default TabCompleteNext, which just cycles the
# matches inline one at a time. Path completion is case-insensitive by default,
# matching zsh's matcher-list; for zsh-style fuzzy/substring matching use the fzf
# trigger on Ctrl+t below (the equivalent of `**<TAB>` in zsh).
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
# Show parameter tooltips alongside the completion menu (like zsh's description format).
Set-PSReadLineOption -ShowToolTips
Set-PSReadLineKeyHandler -Key Ctrl+r -Function ReverseSearchHistory

# FROM: https://github.com/PowerShell/PSReadLine/issues/759#issuecomment-518363364
# Set-PSReadLineKeyHandler -Chord 'j' -ScriptBlock {
# 	if ([Microsoft.PowerShell.PSConsoleReadLine]::InViInsertMode()) {
# 		$key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
# 		if ($key.Character -eq 'k') {
# 			[Microsoft.PowerShell.PSConsoleReadLine]::ViCommandMode()
# 		}
# 		else {
# 			[Microsoft.Powershell.PSConsoleReadLine]::Insert('j')
# 			[Microsoft.Powershell.PSConsoleReadLine]::Insert($key.Character)
# 		}
# 	}
# }

# REMOVE gl, so that we can use gl.bat for git pull instead of Get-Location
Remove-Alias -Force -Name gl
Remove-Alias -Force -Name gp
Remove-Alias -Force -Name gm


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
# LINUX ONLY
# function gcm { git commit -m "${_lc#gcm }" # }
# function glog { git logo }
function gl { git logo ${Args} }
function gdog { git dog ${Args} }
function gadog { git adog ${Args} }
function gb { git branch ${Args} }
function gba { git branch --all ${Args} }
function gco { git checkout ${Args} }
function gm { git merge ${Args} }
function gr { git rebase ${Args} }
function gcd { Set-Location $(git rev-parse --show-toplevel) }

# LINUX ONLY
# alias gt='git tag | sort -V | tail'




# For zoxide v0.8.0+
Invoke-Expression (& {
		$hook = if ($PSVersionTable.PSVersion.Major -lt 6) { 'prompt' } else { 'pwd' }
		(zoxide init --hook $hook powershell | Out-String)
})

# fzf fuzzy completion on Ctrl+t, kept SEPARATE from Tab -- this mirrors zsh,
# where normal Tab is menu-select and fzf is its own trigger (`**<TAB>`). Leaving
# this on Tab would hijack every completion into the fzf selector.
Set-PSReadLineKeyHandler -Key Ctrl+t -ScriptBlock { Invoke-FzfTabCompletion }
