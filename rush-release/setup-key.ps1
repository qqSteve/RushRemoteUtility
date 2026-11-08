$ErrorActionPreference = 'Stop'
$openssl = (Get-Command openssl.exe -ErrorAction SilentlyContinue).Source
if (!$openssl) { $openssl = Join-Path $env:ProgramFiles 'Git/usr/bin/openssl.exe' }
if (!(Test-Path $openssl)) { throw 'Install Git for Windows with OpenSSL.' }
$dir = Join-Path $env:LOCALAPPDATA 'RushRemoteUtility-ReleaseKeys'
New-Item -Type Directory -Force -Path $dir | Out-Null
$key = Join-Path $dir 'signing.pem'
$der = Join-Path $dir 'public.der'
if (!(Test-Path $key)) {
    & $openssl genpkey -algorithm Ed25519 -out $key
    if ($LASTEXITCODE) { throw 'Key generation failed' }
}
& $openssl pkey -in $key -pubout -outform DER -out $der
if ($LASTEXITCODE) { throw 'Invalid private key' }
$b = [IO.File]::ReadAllBytes($der)
if ($b.Length -ne 44 -or [BitConverter]::ToString($b,0,12) -ne '30-2A-30-05-06-03-2B-65-70-03-21-00') { throw 'Invalid Ed25519 key' }
Write-Host ('RUSH_UPDATE_PIN = ' + [Convert]::ToBase64String($b,12,32))
Write-Host "Private key for GitHub secret RUSH_SIGNING_KEY is in $key"
