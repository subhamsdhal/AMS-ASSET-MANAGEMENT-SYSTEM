param(
    [string]$baseUrl = "http://localhost:8080/RailwayAMS",
    [string]$defaultPassword = $env:AMS_TEST_PASSWORD
)

if (-not $defaultPassword) {
    Write-Host "Note: Set AMS_TEST_PASSWORD environment variable to run authentication smoke tests." -ForegroundColor Yellow
    $defaultPassword = "test_password_placeholder"
}

$users = @(
    @{ username = "super_admin"; password = $defaultPassword; role = "super_admin" },
    @{ username = "admin"; password = $defaultPassword; role = "admin" },
    @{ username = "emp002"; password = $defaultPassword; role = "asset_manager" },
    @{ username = "emp003"; password = $defaultPassword; role = "dept_head" },
    @{ username = "emp001"; password = $defaultPassword; role = "employee" },
    @{ username = "auditor"; password = $defaultPassword; role = "auditor" }
)

foreach ($u in $users) {
    Write-Host "=========================================="
    Write-Host "Testing User: $($u.username) ($($u.role))"
    $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    
    # 1. Login check
    $loginUri = "$baseUrl/LoginServlet"
    Write-Host "Target endpoint: $loginUri"
}
