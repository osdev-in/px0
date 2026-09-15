[CmdletBinding()]
param(
    [string]$Version = $(if ($env:VERSION) { $env:VERSION } else { 'latest' }),
    [string]$InstallDir = $(if ($env:PX0_INSTALL_DIR) { $env:PX0_INSTALL_DIR } elseif ($env:INSTALL_DIR) { $env:INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA 'px0\bin' }),
    [string]$Repository = $(if ($env:PX0_REPO) { $env:PX0_REPO } else { 'px0-ai/px0' }),
    [switch]$SkipPathUpdate
)

# Native Windows installer. Downloads a signed release artifact into a
# user-writable directory; it never needs Git Bash, WSL, or administrator
# privileges. Checksums are verified before replacing an existing binary.
$ErrorActionPreference = 'Stop'

function Write-Step([string]$Message) { Write-Host "  > $Message" -ForegroundColor DarkYellow }
function Write-OK([string]$Message) { Write-Host "  + $Message" -ForegroundColor Green }
function Invoke-Download([string]$Uri, [string]$OutFile = '') {
    $parameters = @{ Uri = $Uri }
    if ($OutFile) { $parameters.OutFile = $OutFile }
    # Windows PowerShell 5.1 otherwise tries the retired Internet Explorer
    # parser, which can fail before the request reaches GitHub.
    if ($PSVersionTable.PSVersion.Major -lt 6) { $parameters.UseBasicParsing = $true }
    Invoke-WebRequest @parameters
}
function Get-SHA256([string]$Path) {
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($stream)
        return ([System.BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
    }
    finally {
        $stream.Dispose()
    }
}

switch ($env:PROCESSOR_ARCHITECTURE) {
    'AMD64' { $architecture = 'amd64' }
    'ARM64' { $architecture = 'arm64' }
    'x86'   { $architecture = '386' }
    default { throw "Unsupported Windows architecture: $env:PROCESSOR_ARCHITECTURE" }
}

if ($Version -eq 'latest') {
    Write-Step "Finding the latest px0 release for windows/$architecture..."
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repository/releases/latest" -Headers @{ 'User-Agent' = 'px0-installer' }
    $Version = $release.tag_name.TrimStart('v')
}
if ([string]::IsNullOrWhiteSpace($Version)) { throw 'No px0 version was specified or discovered.' }
$Version = $Version.TrimStart('v')

$binaryName = "px0-$Version-windows-$architecture.exe"
$baseURL = "https://github.com/$Repository/releases/download/v$Version"
$target = Join-Path $InstallDir 'px0.exe'
$temporary = Join-Path ([System.IO.Path]::GetTempPath()) ("px0-$([guid]::NewGuid().ToString('N'))")

try {
    New-Item -ItemType Directory -Force -Path $temporary | Out-Null
    $download = Join-Path $temporary $binaryName
    Write-Step "Downloading $binaryName..."
    Invoke-Download -Uri "$baseURL/$binaryName" -OutFile $download

    $checksumResponse = Invoke-Download -Uri "$baseURL/checksums.txt"
    $checksums = if ($checksumResponse.Content -is [byte[]]) {
        [System.Text.Encoding]::UTF8.GetString($checksumResponse.Content)
    } else {
        [string]$checksumResponse.Content
    }
    $checksumLine = $checksums -split '\r?\n' | Where-Object { $_ -match ('\s' + [regex]::Escape($binaryName) + '$') } | Select-Object -First 1
    if (-not $checksumLine) { throw "No checksum for $binaryName was published with this release." }
    $expected = ($checksumLine -split '\s+')[0].ToLowerInvariant()
    $actual = Get-SHA256 $download
    if ($actual -ne $expected) { throw "Checksum verification failed for $binaryName." }

    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    Move-Item -Force -LiteralPath $download -Destination $target
    Write-OK "Installed px0 v$Version to $target"
}
finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -Recurse -Force -LiteralPath $temporary }
}

$pathEntries = @($env:Path -split ';')
if (-not $SkipPathUpdate -and $pathEntries -notcontains $InstallDir) {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $userEntries = @($userPath -split ';' | Where-Object { $_ })
    if ($userEntries -notcontains $InstallDir) {
        [Environment]::SetEnvironmentVariable('Path', (($userEntries + $InstallDir) -join ';'), 'User')
    }
    $env:Path = "$InstallDir;$env:Path"
    Write-OK "Added $InstallDir to your user PATH. Open a new terminal after this one."
}

Write-Host ''
Write-Host 'Run px0 . to inspect the current directory.'
