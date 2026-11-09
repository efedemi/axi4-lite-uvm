<#
.SYNOPSIS
  Compile, elaborate and run one test on Vivado XSim.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File sim\run.ps1 -Test axil_full_test -Seed 7
  powershell -ExecutionPolicy Bypass -File sim\run.ps1 -Test axil_full_test -Define BUG_WSTRB_IGNORED
  powershell -ExecutionPolicy Bypass -File sim\run.ps1 -Test axil_smoke_test -Waves

.NOTES
  Build output goes to %LOCALAPPDATA%\uvm_build\axi4_lite\<config>, outside the repo:
  OneDrive locks XSim's temp files and breaks elaboration if they live in a synced folder.
  Set $env:XILINX_BIN to override the Vivado bin path.
#>
param(
  [string]   $Test      = "axil_full_test",
  [int]      $Seed      = 1,
  [string[]] $Define    = @(),
  [string]   $Verbosity = "UVM_LOW",
  [switch]   $Waves,
  [switch]   $NoCompile,
  [string]   $CovName   = ""
)

$ErrorActionPreference = "Stop"
$bin  = if ($env:XILINX_BIN) { $env:XILINX_BIN } else { "C:\AMDDesignTools\2025.2\Vivado\bin" }
# Forward slashes: XSim turns backslashes in `__FILE__` paths into escape sequences.
$root = (Split-Path -Parent $PSScriptRoot) -replace '\\', '/'

$defs = @($Define)
if ($Waves) { $defs += "DUMP_WAVES" }
$config = if ($defs.Count) { ($defs | Sort-Object) -join "_" } else { "clean" }
$build  = Join-Path $env:LOCALAPPDATA "uvm_build\axi4_lite\$config"
New-Item -ItemType Directory -Force $build | Out-Null

$sources = @(
  "$root/rtl/axil_regfile.sv",
  "$root/tb/axil_if.sv",
  "$root/tb/axil_pkg.sv",
  "$root/tb/axil_sva.sv",
  "$root/tb/tb_top.sv"
)

Push-Location $build
try {
  if (-not $NoCompile) {
    $defArgs = @(); foreach ($d in $defs) { $defArgs += @("-d", $d) }
    & "$bin\xvlog.bat" -sv -L uvm -i "$root/tb" @defArgs @sources | Out-File -Encoding utf8 compile.log
    if ($LASTEXITCODE -ne 0) { Get-Content compile.log | Select-String "ERROR"; throw "xvlog failed" }
    & "$bin\xelab.bat" tb_top -L uvm -timescale 1ns/1ps -s tb_snap -debug typical | Out-File -Encoding utf8 elab.log
    if ($LASTEXITCODE -ne 0) { Get-Content elab.log | Select-String "ERROR"; throw "xelab failed" }
  }

  if (-not $CovName) { $CovName = "${Test}_s$Seed" }
  $log = "$Test.s$Seed.log"
  # Options go through a file: xsim.bat would split "UVM_TESTNAME=x" at the '='.
  @("-R", "-sv_seed $Seed",
    "-testplusarg UVM_TESTNAME=$Test", "-testplusarg UVM_VERBOSITY=$Verbosity",
    "-cov_db_dir covdb", "-cov_db_name $CovName", "-log $log") |
    Set-Content -Encoding ascii "$Test.s$Seed.args"
  & "$bin\xsim.bat" tb_snap -f "$Test.s$Seed.args" | Out-Null

  $out = Get-Content $log
  $out | Select-String -Pattern "UVM_ERROR(?! :)|UVM_FATAL(?! :)|\[SCB\] checked|\[COV\]|^\s+(op|wdata|req_wait|op x|TOTAL)|RESULT|Error:" |
    ForEach-Object { $_.Line }
  if ($Waves) { Write-Host "waves: $build\waves.vcd" }
  Write-Host "log:   $build\$log"
  if ($out -match "\*\* TEST PASSED \*\*") { exit 0 } else { exit 1 }
} finally {
  Pop-Location
}
