<#
.SYNOPSIS
Install or upgrade the offline Gitea runner from this bundle (Windows hosts
running Docker Desktop with Linux containers).

.DESCRIPTION
Safe to run again: each run verifies the bundle, loads its images, refreshes
compose.yaml, re-imports the actions and restarts the runner. Site settings
(.env, config.yaml, job.env, ca-certificates\, data\) are never overwritten.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Prune
#>
[CmdletBinding()]
param(
    [string]$Dir = $(if ($env:GITEA_RUNNER_DIR) { $env:GITEA_RUNNER_DIR } else { Join-Path $HOME 'gitea-runner' }),
    [switch]$SkipActions,
    [switch]$NoStart,
    [switch]$Prune
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3
$Bundle = $PSScriptRoot
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Say([string]$Message) { Write-Host "`n==> $Message" -ForegroundColor Cyan }
function Fail([string]$Message) { Write-Host "ERROR: $Message" -ForegroundColor Red; exit 1 }

# Windows PowerShell turns redirected native stderr into terminating errors
# under ErrorActionPreference=Stop, so docker runs with Continue and callers
# check the exit code. Output goes straight to the console.
function Invoke-Docker {
    $ErrorActionPreference = 'Continue'
    & docker @args | Out-Host
    return $LASTEXITCODE
}
function Test-Docker {
    $ErrorActionPreference = 'Continue'
    & docker @args *> $null
    return ($LASTEXITCODE -eq 0)
}
function Assert-Docker([string]$What) {
    $code = Invoke-Docker @args
    if ($code -ne 0) { Fail "$What failed (exit code $code)." }
}

function Write-Text([string]$Path, [string]$Text) {
    # Compose misreads a .env that starts with a byte-order mark.
    [System.IO.File]::WriteAllText($Path, $Text.Replace("`r`n", "`n"), $Utf8NoBom)
}

function Get-EnvValue([string]$Key) {
    $path = Join-Path $Dir '.env'
    if (-not (Test-Path -LiteralPath $path)) { return '' }
    $line = Get-Content -LiteralPath $path | Where-Object { $_.StartsWith("$Key=") } | Select-Object -Last 1
    if (-not $line) { return '' }
    return $line.Substring($Key.Length + 1).Trim().Trim('"').Trim("'")
}

function Set-EnvValue([string]$Key, [string]$Value) {
    $path = Join-Path $Dir '.env'
    $found = $false
    $lines = @(Get-Content -LiteralPath $path | ForEach-Object {
        if ($_.StartsWith("$Key=")) { $found = $true; "$Key=$Value" } else { $_ }
    })
    if (-not $found) { $lines += "$Key=$Value" }
    Write-Text $path (($lines -join "`n") + "`n")
}

$Version = (Get-Content -LiteralPath (Join-Path $Bundle 'VERSION') -Raw).Trim()
$BaseImage = "runner-base:$Version"
Say "Gitea offline runner bundle $Version -> $Dir"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Fail 'docker is not installed or not on PATH.' }
if (-not (Test-Docker info)) { Fail 'Cannot reach the Docker daemon. Is Docker Desktop running?' }
if (-not (Test-Docker compose version)) { Fail "The Docker Compose v2 plugin ('docker compose') is required." }
$osType = & docker info --format '{{.OSType}}' 2>$null
if ($osType -ne 'linux') { Fail 'Docker must be in Linux containers mode (Docker Desktop > Switch to Linux containers).' }

Say 'Verifying bundle checksums'
foreach ($line in Get-Content -LiteralPath (Join-Path $Bundle 'SHA256SUMS')) {
    if ($line -notmatch '^([0-9a-fA-F]{64})\s+\*?(.+)$') { continue }
    $expected = $Matches[1].ToUpperInvariant()
    $file = Join-Path $Bundle ($Matches[2] -replace '^\./', '')
    if (-not (Test-Path -LiteralPath $file)) { Fail "Missing $($Matches[2]). Copy the bundle from the media again." }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $file).Hash -ne $expected) {
        Fail "Checksum mismatch for $($Matches[2]). Copy the bundle from the media again."
    }
}

New-Item -ItemType Directory -Force -Path (Join-Path $Dir 'data'), (Join-Path $Dir 'ca-certificates') | Out-Null
$envFile = Join-Path $Dir '.env'
if (-not (Test-Path -LiteralPath $envFile)) {
    Write-Text $envFile (Get-Content -LiteralPath (Join-Path $Bundle '.env.example') -Raw)
    foreach ($key in 'GITEA_INSTANCE_URL', 'GITEA_RUNNER_REGISTRATION_TOKEN', 'GITEA_RUNNER_NAME', 'GITEA_ACTIONS_TOKEN') {
        $value = [Environment]::GetEnvironmentVariable($key)
        if ($value) { Set-EnvValue $key $value }
    }
}

$url = (Get-EnvValue 'GITEA_INSTANCE_URL').TrimEnd('/')
if (-not $url -or $url -like '*gitea.example.internal*') {
    Fail "Set GITEA_INSTANCE_URL (and GITEA_RUNNER_REGISTRATION_TOKEN for the first install) in $envFile, then run this again."
}
$runnerFile = Join-Path $Dir 'data\.runner'
function Test-Registered {
    $item = Get-Item -Force -LiteralPath $runnerFile -ErrorAction SilentlyContinue
    return ($null -ne $item -and $item.Length -gt 0)
}
if (-not (Test-Registered) -and -not (Get-EnvValue 'GITEA_RUNNER_REGISTRATION_TOKEN')) {
    Fail "This runner is not registered yet: set GITEA_RUNNER_REGISTRATION_TOKEN in $envFile, then run this again."
}

Say 'Loading images (several minutes on slow media)'
Assert-Docker 'Loading images' load --input (Join-Path $Bundle 'images\images.tar.gz')

Say 'Writing configuration'
Copy-Item -LiteralPath (Join-Path $Bundle 'compose.yaml') -Destination (Join-Path $Dir 'compose.yaml') -Force
Copy-Item -LiteralPath (Join-Path $Bundle 'manifest.json') -Destination (Join-Path $Dir 'manifest.json') -Force
$jobEnv = Join-Path $Dir 'job.env'
if (-not (Test-Path -LiteralPath $jobEnv)) { Write-Text $jobEnv (Get-Content -LiteralPath (Join-Path $Bundle 'job.env.example') -Raw) }
$template = (Get-Content -LiteralPath (Join-Path $Bundle 'config.yaml.template') -Raw).Replace('@GITEA_INSTANCE_URL@', $url).Replace("`r`n", "`n")
$config = Join-Path $Dir 'config.yaml'
$oldTemplate = Join-Path $Dir 'config.yaml.template'
if (-not (Test-Path -LiteralPath $config)) {
    Write-Text $config $template
    Write-Host "Created $config"
} elseif ((Test-Path -LiteralPath $oldTemplate) -and ((Get-Content -LiteralPath $oldTemplate -Raw) -ne $template)) {
    Write-Host 'Kept your config.yaml. This bundle changed the recommended settings; merge what you need:'
    Compare-Object (Get-Content -LiteralPath $oldTemplate) ($template -split "`n") |
        ForEach-Object { if ($_.SideIndicator -eq '=>') { "+ $($_.InputObject)" } else { "- $($_.InputObject)" } }
} elseif (-not (Test-Path -LiteralPath $oldTemplate) -and ((Get-Content -LiteralPath $config -Raw) -ne $template)) {
    Write-Host "Kept your config.yaml. Compare it with config.yaml.template for this bundle's recommended settings."
}
Write-Text $oldTemplate $template

Say 'Building the CA trust store for the runner and jobs'
$certs = @(Get-ChildItem -LiteralPath (Join-Path $Dir 'ca-certificates') -Filter '*.crt' -File -Recurse).Count
Assert-Docker 'Creating the CA volume' volume create gitea-runner-ca
Assert-Docker 'Building the CA trust store' run --rm --user root --network none `
    -v gitea-runner-ca:/out `
    -v "$(Join-Path $Dir 'ca-certificates'):/usr/local/share/ca-certificates/site:ro" `
    $BaseImage bash -euc 'update-ca-certificates >/dev/null 2>&1; find /out -mindepth 1 -delete; cp -rL /etc/ssl/certs/. /out/'
Write-Host "Trusting the public CAs plus $certs site certificate(s) from $(Join-Path $Dir 'ca-certificates')"

if (-not $SkipActions) {
    $token = if ($env:GITEA_ACTIONS_TOKEN) { $env:GITEA_ACTIONS_TOKEN } else { Get-EnvValue 'GITEA_ACTIONS_TOKEN' }
    if (-not $token -and -not [Console]::IsInputRedirected) {
        $secure = Read-Host -AsSecureString 'Gitea access token for importing actions (Enter to skip)'
        $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
    }
    if (-not $token) {
        Write-Warning "Skipped importing actions; 'uses: actions/...' steps will fail until you do. Set GITEA_ACTIONS_TOKEN in $envFile and run this again."
    } else {
        Say "Importing actions into $url"
        $previous = $env:GITEA_ACTIONS_TOKEN
        $env:GITEA_ACTIONS_TOKEN = $token
        try {
            Assert-Docker 'Importing actions' run --rm -e "GITEA_INSTANCE_URL=$url" -e GITEA_ACTIONS_TOKEN `
                -v "${Bundle}:/bundle:ro" -v gitea-runner-ca:/etc/ssl/certs:ro `
                $BaseImage bash /bundle/import-actions.sh
        } finally {
            $env:GITEA_ACTIONS_TOKEN = $previous
        }
    }
}

if (-not $NoStart) {
    Say 'Starting the runner'
    Push-Location -LiteralPath $Dir
    try { Assert-Docker 'Starting the runner' compose up --detach --remove-orphans } finally { Pop-Location }
    for ($i = 0; $i -lt 30; $i++) {
        if (Test-Registered) { break }
        Start-Sleep -Seconds 2
    }
    if (Test-Registered) {
        Write-Host 'Runner is registered. Check it under Gitea > Settings > Actions > Runners.'
    } else {
        Write-Warning "The runner has not registered yet. Inspect: cd $Dir; docker compose logs runner"
    }
}

if ($Prune) {
    Say 'Removing job images from other bundle versions'
    $old = @(& docker image ls --format '{{.Repository}}:{{.Tag}}' |
        Where-Object { $_ -match '^runner-[a-z0-9]+:' -and -not $_.EndsWith(":$Version") })
    foreach ($image in $old) {
        if ((Invoke-Docker image rm $image) -ne 0) { Write-Warning "Kept $image (still in use)." }
    }
}

Write-Text (Join-Path $Dir 'VERSION') "$Version`n"
Say "Installed bundle $Version"
