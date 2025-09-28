# Simple Input Script for Kubernetes Deployment Scaling

Write-Host "🚀 Kubernetes Deployment Scaling Tool" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

# Action
Write-Host "1. Scale Action:" -ForegroundColor Yellow
Write-Host "   Examples: scale-up, scale-down" -ForegroundColor Gray
$action = Read-Host "Enter action"

# Namespace Pattern  
Write-Host ""
Write-Host "2. Namespace Pattern:" -ForegroundColor Yellow
Write-Host "   Examples: *dev*, *staging*, *prod*, app-*, * (for all)" -ForegroundColor Gray
$namespacePattern = Read-Host "Enter namespace pattern"

# Deployment Pattern
Write-Host ""
Write-Host "3. Deployment Pattern:" -ForegroundColor Yellow  
Write-Host "   Examples: *integration*, *api*, *worker*, app-*, *frontend*" -ForegroundColor Gray
$deploymentPattern = Read-Host "Enter deployment pattern"

# Replicas (only for scale-up)
$replicas = 1
if ($action -eq "scale-up") {
    Write-Host ""
    Write-Host "4. Number of Replicas:" -ForegroundColor Yellow
    Write-Host "   Examples: 1, 2, 3, 5" -ForegroundColor Gray
    $replicasInput = Read-Host "Enter replicas (default: 1)"
    if ($replicasInput) { $replicas = [int]$replicasInput }
}

# Exclude Deployment Patterns
Write-Host ""
Write-Host "5. Exclude Deployment Patterns (optional):" -ForegroundColor Yellow
Write-Host "   Examples: *prod*, *critical*, *db*, leave empty for none" -ForegroundColor Gray
$excludePatterns = Read-Host "Enter exclude patterns (comma-separated, or press Enter for none)"

# Exclude Namespaces
Write-Host ""
Write-Host "6. Exclude Namespaces (optional):" -ForegroundColor Yellow
Write-Host "   Examples: *prod*, monitoring, logging, leave empty for defaults" -ForegroundColor Gray
Write-Host "   Default excludes: kube-system, kube-public, kube-node-lease" -ForegroundColor Gray
$excludeNamespaces = Read-Host "Enter additional exclude patterns (comma-separated, or press Enter for defaults only)"

# Dry Run
Write-Host ""
Write-Host "7. Dry Run (recommended first time):" -ForegroundColor Yellow
Write-Host "   y = Yes (show what would happen), n = No (actually do it)" -ForegroundColor Gray
$dryRunInput = Read-Host "Dry run? (y/n, default: y)"
$dryRun = $dryRunInput -ne "n"

# Build and show command
Write-Host ""
Write-Host "Generated Command:" -ForegroundColor Green
$command = "KScaleAll.ps1 -Action $action -NamespacePattern '$namespacePattern' -DeploymentPattern '$deploymentPattern'"

if ($action -eq "scale-up") {
    $command += " -Replicas $replicas"
}

if ($excludePatterns.Trim()) {
    $excludePatternsArray = ($excludePatterns -split "," | ForEach-Object { "'$($_.Trim())'" }) -join ","
    $command += " -ExcludePatterns @($excludePatternsArray)"
}

if ($excludeNamespaces.Trim()) {
    $defaultExcludes = "'kube-system','kube-public','kube-node-lease'"
    $customExcludes = ($excludeNamespaces -split "," | ForEach-Object { "'$($_.Trim())'" }) -join ","
    $command += " -ExcludeNamespaces @($defaultExcludes,$customExcludes)"
} else {
    $command += " -ExcludeNamespaces @('kube-system','kube-public','kube-node-lease')"
}

if ($dryRun) {
    $command += " -DryRun"
}

Write-Host $command -ForegroundColor White
Write-Host ""

# Confirm and execute
$confirm = Read-Host "Execute this command? (y/n, default: y)"
if ($confirm -ne "n") {
    Write-Host ""
    Write-Host "Executing..." -ForegroundColor Green
    Invoke-Expression $command
} else {
    Write-Host "Command cancelled." -ForegroundColor Yellow
    Write-Host "You can copy and run the command above manually." -ForegroundColor Gray
}