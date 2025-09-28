param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("scale-down", "scale-up")]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    # Pattern to match deployment names (e.g. *integration*, *staging*, app-*)
    [string]$DeploymentPattern,

    [int]$Replicas = 1,

    # Pattern to match namespaces (e.g. *dev*, *staging*, app-*, etc.)
    [string]$NamespacePattern = "*",

    # Patterns to exclude deployments (partial match)
    [string[]]$ExcludePatterns = @(),

    # Patterns to exclude namespaces
    [string[]]$ExcludeNamespaces = @("kube-system", "kube-public", "kube-node-lease"),

    # Dry run mode - show what would be scaled without actually doing it
    [switch]$DryRun
)

Write-Host "=== Kubernetes Deployment Scaling Across All Namespaces ===" -ForegroundColor Cyan
Write-Host "Action: $Action" -ForegroundColor Yellow
Write-Host "Namespace Pattern: $NamespacePattern" -ForegroundColor Yellow
Write-Host "Deployment Pattern: $DeploymentPattern" -ForegroundColor Yellow
Write-Host "Target Replicas: $(if ($Action -eq 'scale-down') { '0' } else { $Replicas })" -ForegroundColor Yellow
Write-Host "Exclude Patterns: $ExcludePatterns" -ForegroundColor Yellow
Write-Host "Exclude Namespaces: $ExcludeNamespaces" -ForegroundColor Yellow
Write-Host "Dry Run: $DryRun" -ForegroundColor Yellow
Write-Host ""

# Get all namespaces
Write-Host "Getting all namespaces..." -ForegroundColor Green
$allNamespaces = kubectl get namespaces -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 
$namespaces = $allNamespaces -split "`n" | Where-Object { $_.Trim() -ne "" }

Write-Host "Found $($namespaces.Count) total namespaces: $($namespaces -join ', ')" -ForegroundColor Gray

# Filter namespaces by pattern
$matchingNamespaces = $namespaces | Where-Object { $_ -like $NamespacePattern }
Write-Host "After pattern matching '$NamespacePattern': $($matchingNamespaces.Count) namespaces: $($matchingNamespaces -join ', ')" -ForegroundColor Gray

# Filter out excluded namespaces
if ($ExcludeNamespaces.Count -gt 0) {
    $originalCount = $matchingNamespaces.Count
    foreach ($excludePattern in $ExcludeNamespaces) {
        $matchingNamespaces = $matchingNamespaces | Where-Object { $_ -notlike "*$excludePattern*" }
    }
    Write-Host "After exclusions: $originalCount -> $($matchingNamespaces.Count) namespaces (excluded patterns: $($ExcludeNamespaces -join ', '))" -ForegroundColor Gray
}

$namespaces = $matchingNamespaces

if ($namespaces.Count -eq 0) {
    Write-Host "No namespaces found matching pattern '$NamespacePattern' after exclusions." -ForegroundColor Red
    exit
}

Write-Host "Final namespace list ($($namespaces.Count)): $($namespaces -join ', ')" -ForegroundColor Green
Write-Host ""

# Decide target replica count based on action
$targetReplicas = switch ($Action) {
    "scale-down" { 0 }
    "scale-up"   { $Replicas }
}

# Track results
$totalDeployments = 0
$scaledDeployments = 0
$results = @()

# Process each namespace
foreach ($namespace in $namespaces) {
    Write-Host "Checking namespace: $namespace" -ForegroundColor Magenta
    
    # Get deployments in this namespace
    $deploymentOutput = kubectl get deploy -n $namespace -o jsonpath='{range .items[*]}{.metadata.name},{.spec.replicas},{.status.replicas}{"\n"}{end}' 2>$null
    
    if (-not $deploymentOutput -or $deploymentOutput.Trim() -eq "") {
        Write-Host "  No deployments found" -ForegroundColor Gray
        continue
    }

    # Parse deployment info
    $deploymentLines = $deploymentOutput -split "`n" | Where-Object { $_.Trim() -ne "" }
    
    foreach ($line in $deploymentLines) {
        $parts = $line -split ","
        if ($parts.Count -ge 3) {
            $deploymentName = $parts[0]
            $specReplicas = $parts[1]
            $statusReplicas = $parts[2]
            
            $totalDeployments++
            
            # Check if deployment matches the pattern
            if ($deploymentName -like $DeploymentPattern) {
                
                # Check exclusions
                $excluded = $false
                foreach ($excludePattern in $ExcludePatterns) {
                    if ($deploymentName -like "*$excludePattern*") {
                        Write-Host "    $deploymentName - EXCLUDED (matches $excludePattern)" -ForegroundColor Yellow
                        $excluded = $true
                        break
                    }
                }
                
                if (-not $excluded) {
                    $currentReplicas = if ($statusReplicas -eq "<no value>") { "0" } else { $statusReplicas }
                    
                    Write-Host "    $deploymentName - Current: $currentReplicas, Target: $targetReplicas" -ForegroundColor White
                    
                    # Store result
                    $result = [PSCustomObject]@{
                        Namespace = $namespace
                        Deployment = $deploymentName
                        CurrentReplicas = $currentReplicas
                        TargetReplicas = $targetReplicas
                        Action = $Action
                    }
                    $results += $result
                    
                    # Scale the deployment (unless dry run)
                    if (-not $DryRun) {
                        if ($currentReplicas -ne $targetReplicas) {
                            Write-Host "      Scaling to $targetReplicas replicas..." -ForegroundColor Green
                            $scaleResult = kubectl scale deploy $deploymentName -n $namespace --replicas=$targetReplicas 2>&1
                            if ($LASTEXITCODE -eq 0) {
                                Write-Host "      ✓ Successfully scaled" -ForegroundColor Green
                                $scaledDeployments++
                            } else {
                                Write-Host "      ✗ Failed to scale: $scaleResult" -ForegroundColor Red
                            }
                        } else {
                            Write-Host "      → Already at target replica count" -ForegroundColor Cyan
                        }
                    } else {
                        Write-Host "      [DRY RUN] Would scale to $targetReplicas replicas" -ForegroundColor Cyan
                        $scaledDeployments++
                    }
                }
            }
        }
    }
}

# Summary
Write-Host ""
Write-Host "=== SUMMARY ===" -ForegroundColor Cyan
Write-Host "Total deployments scanned: $totalDeployments" -ForegroundColor White
Write-Host "Matching deployments found: $($results.Count)" -ForegroundColor White
Write-Host "Deployments $(if ($DryRun) { "would be " }) scaled: $scaledDeployments" -ForegroundColor White

if ($results.Count -gt 0) {
    Write-Host ""
    Write-Host "=== DETAILED RESULTS ===" -ForegroundColor Cyan
    $results | Format-Table -AutoSize
    
    if ($DryRun) {
        Write-Host ""
        Write-Host "This was a DRY RUN. To actually perform the scaling, run again without -DryRun" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Operation completed." -ForegroundColor Green