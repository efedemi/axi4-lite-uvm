<#
.SYNOPSIS
  Bug-injection check: rebuilds the DUT once per planted bug and confirms the
  testbench FAILS. A bug that the testbench doesn't catch is a verification hole.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File sim\bugs.ps1
#>
param([string]$Test = "axil_full_test", [int]$Seed = 1)

$run   = Join-Path $PSScriptRoot "run.ps1"
$bugs  = @("BUG_WSTRB_IGNORED", "BUG_REG_ALIAS", "BUG_RO_RESP", "BUG_WRCOUNT_ON_ERR",
           "BUG_RVALID_DROP", "BUG_RDATA_UNSTABLE")
$caught = 0

foreach ($b in $bugs) {
  $out  = & powershell -ExecutionPolicy Bypass -File $run -Test $Test -Seed $Seed -Define $b 2>&1
  $failed = ($LASTEXITCODE -ne 0)
  $first = ($out | Select-String "UVM_(ERROR|FATAL) .*\[(SCB|SVA|TIMEOUT|MON)\]" | Select-Object -First 1)
  $who = if ($first) { $first.Matches[0].Groups[2].Value } else { "-" }
  $msg = if ($first) { ($first.Line -replace '^.*\] ', '') } else { "" }
  if ($failed) { $caught++ }
  Write-Host ("{0,-20} {1,-8} first flagged by {2,-7} {3}" -f $b, $(if ($failed) { "CAUGHT" } else { "MISSED" }), $who, $msg)
}
Write-Host ""
Write-Host "$caught / $($bugs.Count) injected bugs caught"
if ($caught -ne $bugs.Count) { exit 1 }
