# Simplified SQL Runner - No dependencies, uses local credential file
# First time setup: .\sql.ps1 -SaveCred
# Usage: .\sql.ps1 "SELECT * FROM table"
# Usage: .\sql.ps1 -f scripts/sql/file.sql

param(
    [Parameter(Position=0)]
    [string]$Query,

    [Alias("f")]
    [string]$File,

    [switch]$SaveCred
)

$credFile = "$PSScriptRoot\.sqlcred"
$server = "tcp:100.80.118.68,49759"
$database = "avov2"
$user = "sa"

if ($SaveCred) {
    $pw = Read-Host -AsSecureString "SQL Password for $user"
    $encrypted = ConvertFrom-SecureString $pw
    $encrypted | Out-File $credFile
    Write-Host "✅ Credentials saved to $credFile" -ForegroundColor Green
    exit 0
}

if (-not (Test-Path $credFile)) {
    Write-Host "❌ No credentials found. Run: .\sql.ps1 -SaveCred" -ForegroundColor Red
    exit 1
}

$encrypted = Get-Content $credFile
$securePw = ConvertTo-SecureString $encrypted
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePw)
$password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)

if ($File) {
    sqlcmd -S $server -d $database -U $user -P $password -i $File
} elseif ($Query) {
    sqlcmd -S $server -d $database -U $user -P $password -Q $Query
} else {
    sqlcmd -S $server -d $database -U $user -P $password
}

$password = $null
