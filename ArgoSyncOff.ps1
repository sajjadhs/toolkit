# Ask user for the ArgoCD project name
$project = Read-Host "Enter the ArgoCD project name"

# Get all applications in the argocd namespace
$apps = kubectl get applications -n argocd -o json | ConvertFrom-Json

# Filter applications by project and patch each
$apps.items | Where-Object { $_.spec.project -eq $project } | ForEach-Object {
    $name = $_.metadata.name
    Write-Host "Patching application: $name in project: $project"
    kubectl patch application $name -n argocd --type=json -p '[{"op":"replace","path":"/spec/syncPolicy/automated","value":{}}]'
}

Write-Host "All Applications in project '$project' have been patched."
