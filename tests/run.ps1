param(
    [string] $SourceFile = (Join-Path $PSScriptRoot '..\D4 HELPv7.1.ahk'),
    [string[]] $TestFile = @('startup', 'lifecycle.ahk', 'config.ahk'),
    [string] $AhkPath = 'AutoHotkey64.exe',
    [string] $ScratchDir = [System.IO.Path]::GetTempPath()
)

$ErrorActionPreference = 'Stop'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$entry = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $SourceFile))
$start = $entry.IndexOf('class GUIManager {', [StringComparison]::Ordinal)
$end = $entry.IndexOf('#HotIf ', [StringComparison]::Ordinal)
if ($start -lt 0 -or $end -le $start) { throw 'Cannot locate application classes.' }
$classes = $entry.Substring($start, $end - $start)
$exitHooks = ([regex]::Matches($entry, '(?m)^OnExit\([^\r\n]+\)\r?$')).Value -join "`n"
$support = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'support.ahk'))
$exe = (Get-Command $AhkPath -CommandType Application).Source

foreach ($test in $TestFile) {
    $path = if ([System.IO.Path]::IsPathRooted($test)) { $test } else { Join-Path $PSScriptRoot $test }
    $name = [System.IO.Path]::GetFileNameWithoutExtension($path)
    $work = Join-Path $ScratchDir ("d4-" + $name + '-' + [guid]::NewGuid().ToString('N'))
    [void][System.IO.Directory]::CreateDirectory($work)
    $probe = Join-Path $work 'probe.ahk'
    $out = Join-Path $work 'stdout.txt'
    $err = Join-Path $work 'stderr.txt'
    if ($test -eq 'startup') {
        # A preloaded observer checks the real entry point while it is idle.
        $app = Join-Path $work ([System.IO.Path]::GetFileName($SourceFile))
        Copy-Item -LiteralPath $SourceFile -Destination $app
        $observer = Join-Path $PSScriptRoot 'startup.ahk'
        $arguments = "/ErrorStdOut=UTF-8 /CP65001 /include `"$observer`" `"$app`""
    } else {
        $body = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $path))
        [System.IO.File]::WriteAllText($probe, "$support`n$classes`n$exitHooks`n$body`nCompleteTest()`n", $utf8)
        $arguments = '/ErrorStdOut=UTF-8 /CP65001 "' + $probe + '"'
    }
    $process = Start-Process -FilePath $exe -ArgumentList $arguments -WorkingDirectory $work `
        -WindowStyle Hidden -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
    if (-not $process.WaitForExit(15000)) {
        $process.Kill()
        $process.WaitForExit()
        throw "$name timed out ($work)"
    }
    $output = [System.IO.File]::ReadAllText($out, $utf8)
    $errors = [System.IO.File]::ReadAllText($err, $utf8)
    if ($process.ExitCode -ne 0 -or $errors -or $output.TrimEnd() -notmatch '(?m)^D4_TEST_COMPLETE$') {
        throw "$name did not finish cleanly (exit $($process.ExitCode), $work) $errors $output"
    }
    Write-Output "PASS $name"
}
