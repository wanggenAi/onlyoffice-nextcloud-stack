$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

$DataRoot = $env:DATA_ROOT
if ([string]::IsNullOrWhiteSpace($DataRoot)) {
  $DataRoot = ".data"
}

$CertPath = Join-Path $DataRoot "caddy/data/caddy/pki/authorities/local/root.crt"

if (-not (Test-Path $CertPath)) {
  Write-Host "Local Caddy CA certificate not found at:"
  Write-Host "  $CertPath"
  Write-Host "Run ./scripts/up.sh first so Caddy can generate it."
  exit 1
}

Write-Host "Installing local Caddy CA into Windows CurrentUser Root trust store..."
Import-Certificate -FilePath $CertPath -CertStoreLocation Cert:\CurrentUser\Root | Out-Null

Write-Host "Done. Restart your browser and test:"
Write-Host "  https://cloud.localhost"
Write-Host "  https://docs.localhost/healthcheck"
