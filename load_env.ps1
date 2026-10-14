# charge .env dans la session powershell courante : . .\load_env.ps1
Get-Content "$PSScriptRoot\.env" | Where-Object { $_ -match '^\s*[^#].*=' } | ForEach-Object {
    $name, $value = $_ -split '=', 2
    Set-Item -Path "Env:$($name.Trim())" -Value $value.Trim()
}
Write-Host ".env charge"

# smart app control (windows) peut bloquer venv\Scripts\dbt.exe, lanceur non signé :
# on appelle dbt via python.exe, qui est signé
$script:VenvPython = "$PSScriptRoot\venv\Scripts\python.exe"
function global:dbt {
    & $script:VenvPython -c "import sys; from dbt.cli.main import cli; sys.exit(cli())" @args
}
