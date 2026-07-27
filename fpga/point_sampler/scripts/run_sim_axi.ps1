# Compiles and simulates the AXI4-Lite wrapper testbench (tb_barycentric_axi),
# which drives real AXI4-Lite write/read handshakes against barycentric_axi
# and checks its own PASS/FAIL directly in simulation output (no separate
# Python golden-model comparison needed here -- the underlying math is
# already verified by run_sim.ps1; this checks the register interface).
#
# Usage: powershell -File scripts\run_sim_axi.ps1   (run from anywhere)

$ErrorActionPreference = "Stop"
$VivadoBin = "C:\AMDDesignTools\2026.1\Vivado\bin"
$root = Split-Path -Parent $PSScriptRoot  # fpga/point_sampler

Push-Location $root
try {
    Write-Host "== Compiling RTL + AXI testbench (xvlog) =="
    & "$VivadoBin\xvlog.bat" -sv rtl\fixed_pkg.sv rtl\barycentric.sv rtl\barycentric_axi.sv sim\tb_barycentric_axi.sv
    if ($LASTEXITCODE -ne 0) { throw "xvlog failed" }

    Write-Host "== Elaborating (xelab) =="
    & "$VivadoBin\xelab.bat" tb_barycentric_axi -s barycentric_axi_snapshot
    if ($LASTEXITCODE -ne 0) { throw "xelab failed" }

    Write-Host "== Simulating (xsim) =="
    & "$VivadoBin\xsim.bat" barycentric_axi_snapshot -R | Tee-Object -Variable simOutput
    if ($LASTEXITCODE -ne 0) { throw "xsim failed" }

    if (($simOutput -match "FAILURES").Count -gt 0 -or ($simOutput -match "ALL PASS").Count -eq 0) {
        throw "testbench reported failures (see output above)"
    }

    Write-Host "`nALL GOOD."
}
finally {
    Pop-Location
}
