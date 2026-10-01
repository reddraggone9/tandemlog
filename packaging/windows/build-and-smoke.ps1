$ErrorActionPreference = 'Stop'
$bundle = (Resolve-Path 'build/windows/x64/runner/Release').Path
$dist = New-Item -ItemType Directory -Force dist
$version = (Select-String -Path pubspec.yaml -Pattern '^version: ([^+]+)\+').Matches[0].Groups[1].Value
# Match the minimum runtime to the compiler actually chosen by CMake.
$compilerFiles = @(Get-ChildItem build/windows/x64/CMakeFiles -Recurse -Filter CMakeCXXCompiler.cmake)
if ($compilerFiles.Count -ne 1) { throw 'Cannot identify the exact CMake compiler metadata' }
$compilerText = Get-Content $compilerFiles[0].FullName -Raw
$compilerVersion = [regex]::Match($compilerText, 'CMAKE_CXX_COMPILER_VERSION "19\.(\d+)\.(\d+)\.[^" ]+"')
if (!$compilerVersion.Success) { throw 'Unrecognized MSVC compiler version; runtime prerequisite must be reviewed' }
$runtimeMinor = $compilerVersion.Groups[1].Value
$runtimeBuild = $compilerVersion.Groups[2].Value
$compiler = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6/ISCC.exe'
if (!(Test-Path $compiler)) { throw 'Official Inno Setup 6 compiler absent on hosted runner' }
& $compiler "/DMinRuntimeMinor=$runtimeMinor" "/DMinRuntimeBuild=$runtimeBuild" "/DAppVersion=$version" "/DBundleDir=$bundle" "/DOutputDir=$($dist.FullName)" packaging/windows/tandemlog.iss
if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed' }
$installer = (Resolve-Path dist/tandemlog-windows-x64-unsigned-setup.exe).Path
$installDir = Join-Path $env:LOCALAPPDATA 'Programs/Tandemlog'
$fixture = Join-Path $env:RUNNER_TEMP 'tandemlog-installer-qa'
$report = 'dist/windows-install-smoke.json'
function Install-App {
    $p = Start-Process $installer -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-' -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "Installer exit $($p.ExitCode)" }
    foreach ($file in @('tandemlog.exe','flutter_windows.dll','data/flutter_assets/AssetManifest.bin')) {
        if (!(Test-Path (Join-Path $installDir $file))) { throw "Missing installed $file" }
    }
    foreach ($source in (Get-ChildItem -Path $bundle -Recurse -File)) {
        $relative = $source.FullName.Substring($bundle.Length + 1)
        $installed = Join-Path $installDir $relative
        if (!(Test-Path $installed) -or (Get-FileHash $installed).Hash -ne (Get-FileHash $source.FullName).Hash) {
            throw "Installed payload differs: $relative"
        }
    }
    $shortcut = Join-Path $env:APPDATA 'Microsoft/Windows/Start Menu/Programs/Tandemlog/Tandemlog.lnk'
    if (!(Test-Path $shortcut)) { throw 'Start Menu shortcut absent' }
    $target = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcut).TargetPath
    if ($target -ne (Join-Path $installDir 'tandemlog.exe')) { throw 'Start Menu shortcut targets wrong executable' }
}
Install-App
python packaging/smoke.py --workspace $fixture --report $report --phase after-install --seed -- (Join-Path $installDir 'tandemlog.exe')
if ($LASTEXITCODE -ne 0) { throw 'Installed launch failed' }
# Same-AppId replacement rehearses the upgrade mechanism without fabricating an old build.
Install-App
python packaging/smoke.py --workspace $fixture --report $report --phase after-upgrade -- (Join-Path $installDir 'tandemlog.exe')
if ($LASTEXITCODE -ne 0) { throw 'Replacement launch failed' }
$p = Start-Process (Join-Path $installDir 'unins000.exe') -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART' -Wait -PassThru
if ($p.ExitCode -ne 0 -or (Test-Path (Join-Path $installDir 'tandemlog.exe'))) { throw 'Uninstall failed' }
python packaging/smoke.py --workspace $fixture --report $report --phase after-uninstall
if ($LASTEXITCODE -ne 0) { throw 'Uninstall deleted user data' }
Install-App
python packaging/smoke.py --workspace $fixture --report $report --phase after-reinstall -- (Join-Path $installDir 'tandemlog.exe')
if ($LASTEXITCODE -ne 0) { throw 'Reinstalled launch failed' }
$hash = (Get-FileHash $installer -Algorithm SHA256).Hash.ToLower()
"$hash  tandemlog-windows-x64-unsigned-setup.exe" | Set-Content -Encoding ascii dist/windows-SHA256SUMS.txt
