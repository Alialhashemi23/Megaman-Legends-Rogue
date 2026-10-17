[CmdletBinding()]
param(
 [string]$Script,
 [switch]$Import,
 [int]$TimeoutSeconds = 120,
 [string]$Godot = 'D:\code repos\Megaman-Legends-Rogue\tools\Godot_v4.7.1-stable_win64_console.exe'
)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
# Claude runs in another checkout on the same PC. Do not overlap engine jobs.
$taskBusy = @(Get-CimInstance Win32_Process | Where-Object {
 ($_.Name -like 'Godot*') -or
 ($_.Name -match '^(msedge|chrome|node|emulator|qemu-system).*' -and $_.CommandLine -match 'claude-variety|claude/balance-variety')
})
if ($taskBusy.Count) {
 $taskBusy | ForEach-Object { 'DEFERRED heavy job: {0} PID {1}' -f $_.Name,$_.ProcessId }
 exit 75
}
$taskRuntime = Join-Path $taskRoot 'save/overnight-runtime'
New-Item -ItemType Directory -Force -Path $taskRuntime | Out-Null
$env:APPDATA = $taskRuntime
$env:LOCALAPPDATA = $taskRuntime
$taskLabel = if ($Import) { 'import' } else { [IO.Path]::GetFileNameWithoutExtension($Script) }
if (-not $Import -and -not $Script) { throw 'Specify -Import or -Script' }
$taskInfo = [Diagnostics.ProcessStartInfo]::new($Godot)
$taskInfo.WorkingDirectory = $taskRoot
$taskInfo.UseShellExecute = $false
$taskInfo.CreateNoWindow = $true
$taskInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
$taskInfo.RedirectStandardOutput = $true
$taskInfo.RedirectStandardError = $true
foreach ($taskArg in @('--headless','--path',$taskRoot)) { $taskInfo.ArgumentList.Add($taskArg) }
if ($Import) { foreach ($taskArg in @('--editor','--import')) { $taskInfo.ArgumentList.Add($taskArg) } }
else { foreach ($taskArg in @('--script',$Script)) { $taskInfo.ArgumentList.Add($taskArg) } }
$taskProcess = [Diagnostics.Process]::Start($taskInfo)
$taskStdout = $taskProcess.StandardOutput.ReadToEndAsync()
$taskStderr = $taskProcess.StandardError.ReadToEndAsync()
$taskClock = [Diagnostics.Stopwatch]::StartNew()
$taskTimedOut = $false
while (-not $taskProcess.WaitForExit(250)) {
 if ($taskClock.Elapsed.TotalSeconds -gt $TimeoutSeconds) {
  $taskTimedOut = $true
  $taskProcess.Kill($true)
  $taskProcess.WaitForExit()
  break
 }
}
$taskLog = $taskStdout.GetAwaiter().GetResult() + $taskStderr.GetAwaiter().GetResult()
$taskLogPath = Join-Path $taskRoot "save/overnight-$taskLabel.log"
[IO.File]::WriteAllText($taskLogPath,$taskLog,[Text.UTF8Encoding]::new($false))
($taskLog -split '\r?\n' | Select-Object -Last 10) -join "`n"
if ($taskTimedOut) { throw "Watchdog stopped only this test after $TimeoutSeconds seconds" }
if ($taskProcess.ExitCode -ne 0 -or $taskLog -match 'SCRIPT ERROR|Parse Error|CHECK_FAILED') { throw "$taskLabel failed; see $taskLogPath" }
exit 0
