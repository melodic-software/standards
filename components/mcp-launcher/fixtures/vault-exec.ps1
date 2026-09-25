# Test double for %USERPROFILE%\.local\bin\vault-exec.ps1: same argv contract, no vault.
# Appends its argv to $env:STUB_VAULT_LOG, sets each NAME to stub-<secret> (or leaves
# it unset when STUB_VAULT_MODE=empty, like an --optional miss), then runs the command
# the way the real script does: ProcessStartInfo, stdio inherited, its exit code.
# A nested call exits 99 at once, so a broken loop guard fails fast instead of recursing.
Add-Content -LiteralPath $env:STUB_VAULT_LOG -Value ($args -join ' ')
if ($env:STUB_VAULT_DEPTH) { exit 99 }
$split = [array]::IndexOf($args, '--')
$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.UseShellExecute = $false
$startInfo.Environment['STUB_VAULT_DEPTH'] = '1'
$startInfo.FileName = $args[$split + 1]
for ($index = $split + 2; $index -lt $args.Count; $index++) {
    $startInfo.ArgumentList.Add($args[$index])
}
for ($index = 0; $index -lt $split; $index++) {
    if ($args[$index] -ne '--env') { continue }
    $name, $secret = $args[$index + 1] -split '=', 2
    if ($env:STUB_VAULT_MODE -eq 'empty') {
        [void]$startInfo.Environment.Remove($name)
        [Console]::Error.WriteLine("vault-exec: $name not set: stub; starting without it")
    } else {
        $startInfo.Environment[$name] = "stub-$secret"
    }
}
$process = [System.Diagnostics.Process]::Start($startInfo)
$process.WaitForExit()
exit $process.ExitCode
