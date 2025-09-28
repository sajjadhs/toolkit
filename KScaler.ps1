param(
    [Parameter(Mandatory = $true)]
    [string]$Namespace,

    [Parameter(Mandatory = $true)]
    [ValidateSet("scale-down", "scale-up")]
    [string]$Action,

    [int]$Replicas = 1,

    [Parameter(Mandatory = $true)]
    # Pattern to match deployments (e.g. *integration, *staging, etc.)
    [string]$MatchPattern = "*integration",

    [Parameter(Mandatory = $true)]
    # Pattern to match deployments (e.g. *integration, etc.)
    [string[]]$ExcludePatterns = @()
)

# Get all deployment names in the namespace (fixed jsonpath with newlines)
$deploymentOutput = kubectl get deploy -n $Namespace -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'

if (-not $deploymentOutput) {
    Write-Host "No deployments found in namespace '$Namespace'."
    exit
}

# Convert to array and filter out empty lines
$deployments = $deploymentOutput -split "`n" | Where-Object { $_.Trim() -ne "" }

Write-Host "Found deployments: $($deployments -join ', ')"

# Filter for deployments matching the given pattern
$targetDeployments = $deployments | Where-Object { $_ -like $MatchPattern }

Write-Host "After pattern matching '$MatchPattern': $($targetDeployments -join ', ')"

# Apply exclusions (partial match)
if ($ExcludePatterns.Count -gt 0) {
    foreach ($pattern in $ExcludePatterns) {
        $targetDeployments = $targetDeployments | Where-Object { $_ -notlike "*$pattern*" }
        Write-Host "After excluding '*$pattern*': $($targetDeployments -join ', ')"
    }
}

if (-not $targetDeployments -or $targetDeployments.Count -eq 0) {
    Write-Host "No deployments found in namespace '$Namespace' matching pattern '$MatchPattern' after exclusions."
    exit
}

# Decide replicas based on action
switch ($Action) {
    "scale-down" { $replicaCount = 0 }
    "scale-up"   { $replicaCount = $Replicas }
}

Write-Host "Final target deployments: $($targetDeployments -join ', ')"

# Scale the deployments
foreach ($dep in $targetDeployments) {
    Write-Host "Scaling $dep in namespace $Namespace to $replicaCount replicas..."
    kubectl scale deploy $dep -n $Namespace --replicas=$replicaCount
}