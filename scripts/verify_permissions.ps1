param(
    [string]$baseUrl = "http://localhost:8080/RailwayAMS",
    [string]$defaultPassword = $env:AMS_TEST_PASSWORD
)

if (-not $defaultPassword) {
    Write-Host "Note: Set AMS_TEST_PASSWORD environment variable to run live smoke verification." -ForegroundColor Yellow
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

Write-Host "Starting API verification of roles and permissions..."

foreach ($u in $users) {
    Write-Host "`n--- Testing Role: $($u.role) (User: $($u.username)) ---"
    $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    
    # 1. Login
    $loginBody = "username=$($u.username)&password=$($u.password)"
    $loginResp = Invoke-WebRequest -Uri "$baseUrl/LoginServlet" -Method Post -Body $loginBody -ContentType "application/x-www-form-urlencoded" -WebSession $session -ErrorAction SilentlyContinue -MaximumRedirection 0

    if ($loginResp.StatusCode -eq 302 -or $loginResp.StatusCode -eq 200) {
        Write-Host "Login: SUCCESS"
    } else {
        Write-Host "Login: FAILED (Status: $($loginResp.StatusCode))"
        continue
    }
    
    # 2. Dashboard
    $dashResp = Invoke-WebRequest -Uri "$baseUrl/dashboard.jsp" -WebSession $session -ErrorAction SilentlyContinue
    if ($dashResp.Content -match "Total Assets" -or $dashResp.Content -match "Dashboard") {
        Write-Host "Dashboard: LOADED"
    } else {
        Write-Host "Dashboard: FAILED/PARTIAL"
    }
    
    # 3. Assets Page
    $assetsResp = Invoke-WebRequest -Uri "$baseUrl/manage_assets.jsp" -WebSession $session -ErrorAction SilentlyContinue
    if ($assetsResp.StatusCode -ne 200) {
        $assetsResp = Invoke-WebRequest -Uri "$baseUrl/assets.jsp" -WebSession $session -ErrorAction SilentlyContinue
    }
    
    if ($assetsResp.StatusCode -eq 200) {
        Write-Host "Assets Page: LOADED"
        $content = $assetsResp.Content
        
        $addPresent = ($content -match "Add Asset" -or $content -match "add_asset.jsp")
        $editPresent = ($content -match "Edit" -or $content -match "edit_asset.jsp")
        $disposePresent = ($content -match "Dispose" -or $content -match "dispose_asset.jsp")
        $exportPresent = ($content -match "Export" -or $content -match "export_asset")
        
        Write-Host "Permissions on Assets Page:"
        Write-Host "  Add Asset Allowed: $addPresent"
        Write-Host "  Edit Asset Allowed: $editPresent"
        Write-Host "  Dispose Asset Allowed: $disposePresent"
        Write-Host "  Export Asset Allowed: $exportPresent"
    } else {
        Write-Host "Assets Page: ACCESS DENIED or NOT FOUND ($($assetsResp.StatusCode))"
    }
}
