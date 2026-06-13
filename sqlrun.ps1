# SQL Runner - Easy database queries using Windows Credential Manager
#
# SETUP (one-time):
#   Run: .\sqlrun.ps1 -Setup
#   Enter password when prompted
#
# USAGE:
#   .\sqlrun.ps1 -Query "SELECT * FROM sys.objects"
#   .\sqlrun.ps1 -File "scripts\sql\00-VERIFICATION.sql"
#   .\sqlrun.ps1  (interactive mode)

param(
    [Parameter(Mandatory=$false)]
    [string]$Query,

    [Parameter(Mandatory=$false)]
    [string]$File,

    [Parameter(Mandatory=$false)]
    [switch]$Setup,

    [Parameter(Mandatory=$false)]
    [string]$Server = "tcp:100.80.118.68,49759",

    [Parameter(Mandatory=$false)]
    [string]$Database = "avov2",

    [Parameter(Mandatory=$false)]
    [string]$User = "sa",

    [Parameter(Mandatory=$false)]
    [string]$CredentialTarget = "SQLServerAvov2"
)

# Check if CredentialManager module is available
if (-not (Get-Module -ListAvailable -Name CredentialManager)) {
    Write-Host "⚠️  CredentialManager module not found" -ForegroundColor Yellow
    Write-Host "Installing CredentialManager module..." -ForegroundColor Cyan
    Install-Module CredentialManager -Scope CurrentUser -Force
}

Import-Module CredentialManager -ErrorAction Stop

# Setup mode: Store credentials
if ($Setup) {
    Write-Host "🔐 Setting up SQL Server credentials in Windows Credential Manager" -ForegroundColor Green
    Write-Host ""

    $pw = Read-Host -AsSecureString "SQL password for $User@$Server"
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pw)
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)

    New-StoredCredential -Target $CredentialTarget -UserName $User -Password $plain -Persist LocalMachine -ErrorAction SilentlyContinue | Out-Null
    $plain = $null

    Write-Host "✅ Credentials stored successfully!" -ForegroundColor Green
    Write-Host "   Target: $CredentialTarget" -ForegroundColor Cyan
    Write-Host "   UserName: $User" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "You can now run SQL commands without entering password:" -ForegroundColor Yellow
    Write-Host "  .\sqlrun.ps1 -Query `"SELECT * FROM sys.objects`"" -ForegroundColor Cyan
    Write-Host "  .\sqlrun.ps1 -File `"scripts\sql\00-VERIFICATION.sql`"" -ForegroundColor Cyan
    exit 0
}

# Load credential from Windows Credential Manager
try {
    $cred = Get-StoredCredential -Target $CredentialTarget -ErrorAction Stop
} catch {
    Write-Host "❌ Error loading credentials: $_" -ForegroundColor Red
    exit 1
}

if ($null -eq $cred) {
    Write-Host "❌ Credentials not found in Windows Credential Manager" -ForegroundColor Red
    Write-Host ""
    Write-Host "Run setup first:" -ForegroundColor Yellow
    Write-Host "  .\sqlrun.ps1 -Setup" -ForegroundColor Cyan
    exit 1
}

# Debug output
Write-Host "DEBUG: Query='$Query' File='$File'" -ForegroundColor Gray

# Get password as plain text
$password = $cred.GetNetworkCredential().Password

# Build command as a string (more reliable than array splatting)
if ($Query) {
    $cmd = "sqlcmd -S `"$Server`" -d `"$Database`" -U `"$($cred.UserName)`" -P `"$password`" -Q `"$Query`""
}
elseif ($File) {
    if (-not (Test-Path $File)) {
        Write-Host "❌ File not found: $File" -ForegroundColor Red
        exit 1
    }
    $cmd = "sqlcmd -S `"$Server`" -d `"$Database`" -U `"$($cred.UserName)`" -P `"$password`" -i `"$File`""
}
else {
    # Interactive mode
    $cmd = "sqlcmd -S `"$Server`" -d `"$Database`" -U `"$($cred.UserName)`" -P `"$password`""
    Write-Host "🔗 Connecting to $Server/$Database..." -ForegroundColor Cyan
}

# Execute using Invoke-Expression
Invoke-Expression $cmd
