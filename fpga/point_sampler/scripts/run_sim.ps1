# Orchestrates the point_sampler verification flow:
#   1. regenerate golden vectors (Python, mirrors festi's CPU math)
#   2. compile + elaborate + simulate the RTL against them (Vivado xsim)
#   3. compare DUT output to the golden model within tolerance
#
# Usage: powershell -File scripts\run_sim.ps1   (run from anywhere)

$ErrorActionPreference = "Stop"
$VivadoBin = "C:\AMDDesignTools\2026.1\Vivado\bin"
$root = Split-Path -Parent $PSScriptRoot  # fpga/point_sampler

Push-Location $root
try {
    Write-Host "== Generating golden vectors =="
    python scripts\gen_vectors.py
    if ($LASTEXITCODE -ne 0) { throw "gen_vectors.py failed" }

    Write-Host "== Compiling RTL + testbench (xvlog) =="
    & "$VivadoBin\xvlog.bat" -sv rtl\fixed_pkg.sv rtl\barycentric.sv sim\tb_barycentric.sv
    if ($LASTEXITCODE -ne 0) { throw "xvlog failed" }

    Write-Host "== Elaborating (xelab) =="
    & "$VivadoBin\xelab.bat" tb_barycentric -s barycentric_snapshot
    if ($LASTEXITCODE -ne 0) { throw "xelab failed" }

    Write-Host "== Simulating (xsim) =="
    & "$VivadoBin\xsim.bat" barycentric_snapshot -R
    if ($LASTEXITCODE -ne 0) { throw "xsim failed" }

    Write-Host "== Comparing DUT output to golden model =="
    python scripts\compare.py
    if ($LASTEXITCODE -ne 0) { throw "compare.py reported a mismatch" }

    Write-Host "`nALL GOOD."
}
finally {
    Pop-Location
}
