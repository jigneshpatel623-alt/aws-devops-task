# One-click bootstrap: creates the Terraform state bucket + GitHub Actions role,
# then starts the CI/CD pipeline.  Right-click this file -> "Run with PowerShell".
$ErrorActionPreference = "Stop"
$env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User") + ";C:\Users\HP\tools\gh\bin"
$env:AWS_PROFILE = "devops-task"

try {
    Set-Location (Join-Path $PSScriptRoot "..\terraform\bootstrap")

    Write-Host "`n=== Step 1/3: terraform init ===" -ForegroundColor Cyan
    terraform init -input=false
    if ($LASTEXITCODE -ne 0) { throw "terraform init failed" }

    Write-Host "`n=== Step 2/3: terraform apply (state bucket + GitHub Actions role) ===" -ForegroundColor Cyan
    terraform apply -input=false -auto-approve
    if ($LASTEXITCODE -ne 0) { throw "terraform apply failed" }
    terraform output

    Write-Host "`n=== Step 3/3: start the GitHub Actions pipeline ===" -ForegroundColor Cyan
    gh workflow run terraform.yml -R jigneshpatel623-alt/aws-devops-task --ref main
    if ($LASTEXITCODE -ne 0) { throw "could not start the workflow" }

    Write-Host "`nDONE. Bootstrap created and pipeline started." -ForegroundColor Green
    Write-Host "Go back to Claude Code and type: check run" -ForegroundColor Green
}
catch {
    Write-Host "`nFAILED: $_" -ForegroundColor Red
    Write-Host "Copy the red text above and paste it into Claude Code." -ForegroundColor Red
}
Read-Host "`nPress Enter to close"
