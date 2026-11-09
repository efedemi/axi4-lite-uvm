<#
.SYNOPSIS
  Multi-seed regression: builds once, runs every test across N seeds, merges
  functional coverage with xcrg, prints a pass/fail table.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File sim\regress.ps1 -Seeds 10
#>
param(
  [int]      $Seeds = 10,
  [string[]] $Tests = @("axil_full_test", "axil_random_test", "axil_error_test", "axil_directed_test")
)

$ErrorActionPreference = "Stop"
$bin   = if ($env:XILINX_BIN) { $env:XILINX_BIN } else { "C:\AMDDesignTools\2025.2\Vivado\bin" }
$run   = Join-Path $PSScriptRoot "run.ps1"
$build = Join-Path $env:LOCALAPPDATA "uvm_build\axi4_lite\clean"

# fresh coverage database for this regression
Remove-Item -Recurse -Force "$build\covdb" -ErrorAction SilentlyContinue

# build once
& powershell -ExecutionPolicy Bypass -File $run -Test axil_smoke_test -Seed 1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw "build or smoke test failed" }
Remove-Item -Recurse -Force "$build\covdb" -ErrorAction SilentlyContinue

$results = @()
foreach ($t in $Tests) {
  for ($s = 1; $s -le $Seeds; $s++) {
    & powershell -ExecutionPolicy Bypass -File $run -Test $t -Seed $s -NoCompile | Out-Null
    $pass = ($LASTEXITCODE -eq 0)
    $log  = Get-Content "$build\$t.s$s.log"
    $cov  = ($log | Select-String "TOTAL FUNCTIONAL COVERAGE\s+([\d.]+)%" | Select-Object -Last 1).Matches.Groups[1].Value
    $chk  = ($log | Select-String "checked (\d+) writes, (\d+) reads" | Select-Object -Last 1).Matches
    $n    = if ($chk) { [int]$chk.Groups[1].Value + [int]$chk.Groups[2].Value } else { 0 }
    $results += [pscustomobject]@{ Test = $t; Seed = $s; Result = $(if ($pass) { "PASS" } else { "FAIL" }); Checked = $n; Coverage = "$cov%" }
    Write-Host ("{0,-20} seed {1,3}  {2}  {3,5} txns  cov {4}%" -f $t, $s, $(if ($pass) { "PASS" } else { "FAIL" }), $n, $cov)
  }
}

# merge coverage from every run
Push-Location $build
try {
  $dbs = Get-ChildItem "covdb\xsim.covdb" -Directory | ForEach-Object { $_.Name }
  $args = @("-dir", "covdb\xsim.covdb")
  foreach ($d in $dbs) { $args += @("-db_name", $d) }
  & "$bin\xcrg.bat" @args -merge_dir merged -merge_db_name all -report_dir cov_report -report_format text | Out-File -Encoding utf8 xcrg.log
  $summary = Get-ChildItem cov_report -Recurse -Filter *.txt -ErrorAction SilentlyContinue | Select-Object -First 1
} finally { Pop-Location }

$fails = @($results | Where-Object Result -eq "FAIL").Count
Write-Host ""
Write-Host ("{0} runs, {1} passed, {2} failed, {3} transactions checked" -f $results.Count, ($results.Count - $fails), $fails, ($results | Measure-Object Checked -Sum).Sum)
if ($summary) { Write-Host "merged coverage report: $($summary.FullName)" }
else          { Write-Host "xcrg log: $build\xcrg.log" }
if ($fails) { exit 1 } else { exit 0 }
