param([Parameter(Mandatory)][ValidateSet('Prepare','Queue','Apply')][string]$Action)
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:ProgramFiles 'RushRemoteUtility Maintenance'
if ($PSScriptRoot -ine $root) { throw 'Unexpected maintenance directory' }
$install = Join-Path $env:ProgramFiles 'RushRemoteUtility'
$old = Join-Path $root previous
$stage = Join-Path $root staged
$pending = Join-Path $root pending
$task = 'RushRemoteUtility Update'
$service = 'RushRemoteUtility'
function Status([string]$s) { [IO.File]::WriteAllText((Join-Path $root 'status.txt'), $s) }
function Stop-Client {
    Stop-Service -Name $service -Force
    (Get-Service $service).WaitForStatus('Stopped',[TimeSpan]::FromSeconds(30))
    Get-CimInstance Win32_Process -Filter "Name='RushRemoteUtility.exe'" | Where-Object {
        $_.ExecutablePath -ieq (Join-Path $install 'RushRemoteUtility.exe')
    } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}
function Start-Client {
    Start-Service $service
    (Get-Service $service).WaitForStatus('Running',[TimeSpan]::FromSeconds(30))
    Start-Sleep 8
    if ((Get-Service $service).Status -ne 'Running') { throw 'Service startup failed' }
}
function Rollback {
    if (Test-Path $old) {
        Stop-Client
        if (Test-Path $install) { Remove-Item -Recurse -Force -LiteralPath $install }
        [IO.Directory]::Move($old,$install)
    }
    Start-Client
}
if ($Action -eq 'Prepare') {
    if (Test-Path $stage) { Remove-Item -Recurse -Force -LiteralPath $stage }
    Expand-Archive -LiteralPath (Join-Path $root 'package.zip') -DestinationPath $stage
    foreach ($file in 'RushRemoteUtility.exe','librustdesk.dll','data/flutter_assets','rush-version.txt') {
        if (!(Test-Path (Join-Path $stage $file))) { throw "Incomplete package: $file" }
    }
    Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32/RuntimeBroker.exe') -Destination (Join-Path $stage 'RuntimeBroker_rustdesk.exe')
    $shortcut = Join-Path $install 'Uninstall RushRemoteUtility.lnk'
    if (Test-Path $shortcut) { Copy-Item -LiteralPath $shortcut -Destination $stage }
    return
}
if ($Action -eq 'Queue') {
    $shell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $job = New-ScheduledTaskAction -Execute $shell -Argument ('-NonInteractive -NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" Apply')
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $task -Action $job -Trigger (New-ScheduledTaskTrigger -AtStartup) -User SYSTEM -RunLevel Highest -Settings $settings -Force | Out-Null
    [IO.File]::WriteAllText($pending,(Get-Content (Join-Path $stage 'rush-version.txt') -Raw).Trim())
    try { Start-ScheduledTask -TaskName $task } catch { Remove-Item $pending; throw }
    return
}
if (!(Test-Path $pending)) { return }
$lock = [IO.File]::Open((Join-Path $root 'apply.lock'),'OpenOrCreate','ReadWrite','None')
try {
    $v = Get-Content $pending -Raw
    if (Test-Path $old) { throw 'Interrupted installation; restoring previous release' }
    $svc = Get-CimInstance Win32_Service -Filter "Name='RushRemoteUtility'"
    if (!$svc -or $svc.PathName -notlike ('*' + (Join-Path $install 'RushRemoteUtility.exe') + '*')) { throw 'Unexpected service path' }
    $idle = Start-Process -FilePath (Join-Path $install 'RushRemoteUtility.exe') -ArgumentList '--rush-update-idle' -Wait -PassThru
    if ($idle.ExitCode -ne 0) {
        Status 'Deferred: active session or service unavailable.'
        Remove-Item $pending
        return
    }
    Stop-Client
    [IO.Directory]::Move($install,$old)
    [IO.Directory]::Move($stage,$install)
    Start-Client
    # Commit first. Old files can now be cleaned without affecting rollback.
    $retired = Join-Path $root ('retired-' + [Guid]::NewGuid().ToString('N'))
    [IO.Directory]::Move($old,$retired)
    Remove-Item $pending
    Status "Installed $v"
    Remove-Item -Recurse -Force $retired -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $root 'failed.txt') -ErrorAction SilentlyContinue
} catch {
    $reason = $_.Exception.Message
    [IO.File]::WriteAllText((Join-Path $root 'failed.txt'),$v)
    try {
        Rollback
        Remove-Item $pending
        Status "Update failed: $reason. Service restarted."
    } catch {
        Status "Update recovery pending: $reason / $_"
        throw
    }
} finally {
    $lock.Dispose()
    # Keep the recovery task when the disk or the service is unavailable.
    if (!(Test-Path $pending)) { Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue }
}
