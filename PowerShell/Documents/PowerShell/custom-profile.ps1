# Portable: every external tool/module is guarded so this loads anywhere.

# posh-git: import is ~1.3s. oh-my-posh already renders git status in the
# prompt, so posh-git is only here for git tab completion. Defer that cost by
# registering a stub completer for `git` that imports posh-git on first use.
# Importing posh-git re-registers this completer with its own, so the import
# happens exactly once; we delegate that first invocation to posh-git directly.
if (Get-Command git -ErrorAction SilentlyContinue) {
  Register-ArgumentCompleter -Native -CommandName git -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Import-Module posh-git -ErrorAction SilentlyContinue
    if (Get-Command Expand-GitCommand -ErrorAction SilentlyContinue) {
      Expand-GitCommand $commandAst.Extent.Text
    }
  }
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

  # PSFzf: import is ~0.9s and only needed for the Ctrl+t fuzzy completer, so
  # load it on first press. Importing PSFzf may rebind Ctrl+t to its own default,
  # so re-assert our binding afterwards, then run the completion for this press.
  if (Get-Command fzf -ErrorAction SilentlyContinue) {
    Set-PSReadLineKeyHandler -Key Ctrl+t -ScriptBlock {
      Import-Module PSFzf -ErrorAction SilentlyContinue
      if (Get-Command Invoke-FzfTabCompletion -ErrorAction SilentlyContinue) {
        Set-PSReadLineKeyHandler -Key Ctrl+t -ScriptBlock { Invoke-FzfTabCompletion }
        Invoke-FzfTabCompletion
      }
    }
  }
}

# Substring ("contains") directory completion for cd/pushd, like zsh's matcher-list
# (e.g. `cd Orca<Tab>` completes TIL.Orca). -Force includes dotdirs (zsh globdots).
$SubstringDirCompleter = {
  param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
  $word   = $wordToComplete.Trim("'`"")
  $parent = Split-Path -Path $word -Parent
  $leaf   = Split-Path -Path $word -Leaf
  $searchDir = if ([string]::IsNullOrEmpty($parent)) { '.' } else { $parent }
  Get-ChildItem -LiteralPath $searchDir -Directory -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like "*$leaf*" } |
    Sort-Object Name |
    ForEach-Object {
      $path = if ([string]::IsNullOrEmpty($parent)) { $_.Name } else { Join-Path $parent $_.Name }
      $text = if ($path -match '\s') { "'$path'" } else { $path }
      [System.Management.Automation.CompletionResult]::new($text, $_.Name, 'ProviderContainer', $_.FullName)
    }
}
Register-ArgumentCompleter -CommandName cd, sl, Set-Location, pushd, Push-Location -ParameterName Path -ScriptBlock $SubstringDirCompleter

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
