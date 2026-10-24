# SOURCE-ONLY bounded external wrapper; requires existing PowerShell7/Python.
# No application run is enabled in the build-only workflow.
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Artifact,
  [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$ManifestSha256,
  [Parameter(Mandatory=$true)][string]$Fixture
)
$ErrorActionPreference = 'Stop'
if (!$IsWindows -or $PSVersionTable.PSVersion.Major -lt 7) {
  throw 'Use existing Windows PowerShell7; do not install/change runtime.'
}
$controller = Join-Path $PSScriptRoot 'windows_widget_controller.py'
if (!(Test-Path -LiteralPath $controller -PathType Leaf)) { throw 'Controller missing.' }
$python = (Get-Command python -CommandType Application | Select-Object -First 1).Source
if (!$python -or $python -match '\\WindowsApps\\') { throw 'Existing real Python required.' }
$info = [System.Diagnostics.ProcessStartInfo]::new()
$info.FileName = $python
$info.UseShellExecute = $false
$info.CreateNoWindow = $true
$info.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
$info.RedirectStandardOutput = $true
$info.RedirectStandardError = $true
foreach ($argument in @($controller, '--artifact', $Artifact,
                       '--manifest-sha256', $ManifestSha256, '--fixture', $Fixture)) {
  $info.ArgumentList.Add($argument)
}
$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $info
$outerTimedOut = $false
$started = $false
$logRoot = Join-Path ([IO.Path]::GetTempPath()) ('windows-widget-wrapper-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $logRoot | Out-Null
try {
  if (!$process.Start()) { throw 'Controller launch failed.' }
  $started = $true
  $ownedPid = $process.Id
  $ownedStart = $process.StartTime.ToUniversalTime().Ticks
  $stdout = $process.StandardOutput.ReadToEndAsync()
  $stderr = $process.StandardError.ReadToEndAsync()
  if (!$process.WaitForExit(170000)) {
    $outerTimedOut = $true
    # Retained Process handle + PID/start-time check, never name-wide kill.
    $live = Get-Process -Id $ownedPid -ErrorAction Stop
    if ($live.StartTime.ToUniversalTime().Ticks -ne $ownedStart -or
        $live.Path -ne $python) { throw 'Owned controller identity no longer matches.' }
    $process.Kill() # Controller only; closing its Job handles kills owned app.
    if (!$process.WaitForExit(5000)) { throw 'Owned controller did not stop.' }
  }
  if (!$stdout.Wait(1000) -or !$stderr.Wait(1000)) { throw 'Bounded pipe drain failed.' }
  [IO.File]::WriteAllText((Join-Path $logRoot 'controller.stdout.jsonl'), $stdout.Result)
  [IO.File]::WriteAllText((Join-Path $logRoot 'controller.stderr.log'), $stderr.Result)
  $receipt = @{
    controllerPid = $ownedPid
    controllerStartUtcTicks = $ownedStart
    outerTimedOut = $outerTimedOut
    exitCode = $process.ExitCode
    controllerSHA256 = (Get-FileHash -LiteralPath $controller -Algorithm SHA256).Hash.ToLowerInvariant()
    pythonSHA256 = (Get-FileHash -LiteralPath $python -Algorithm SHA256).Hash.ToLowerInvariant()
    manifestSHA256 = $ManifestSha256
    passed = (!$outerTimedOut -and $process.ExitCode -eq 0)
    qualification = 'Native inactive-Desktop release QA; framework input/frame only, not presentation or installer.'
  }
  $receipt | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $logRoot 'wrapper-result.json')
  Write-Output ($receipt | ConvertTo-Json -Compress)
  if (!$receipt.passed) { throw ('QA failed; retained wrapper logs: ' + $logRoot) }
} finally {
  # Failure cleanup can only target the Process object launched by this wrapper.
  if ($started -and !$process.HasExited) {
    $process.Kill()
    [void]$process.WaitForExit(5000)
  }
  $process.Dispose()
}
