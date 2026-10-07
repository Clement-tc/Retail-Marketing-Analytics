# charge .env dans la session powershell courante : . .\load_env.ps1
Get-Content "$PSScriptRoot\.env" | Where-Object { $_ -match '^\s*[^#].*=' } | ForEach-Object {
    $name, $value = $_ -split '=', 2
    Set-Item -Path "Env:$($name.Trim())" -Value $value.Trim()
}
Write-Host ".env charge"
