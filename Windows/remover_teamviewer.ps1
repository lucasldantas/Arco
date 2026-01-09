$app = "TeamViewer"
Write-Host "Iniciando a busca e remoção do $app..." -ForegroundColor Cyan

$paths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

foreach ($path in $paths) {
    $found = Get-ItemProperty $path | Where-Object { $_.DisplayName -like "*$app*" }

    foreach ($item in $found) {
        $uninstallString = $item.UninstallString
        if ($uninstallString) {
            Write-Host "Removendo: $($item.DisplayName)..." -ForegroundColor Yellow
            $uninstallPath = $uninstallString.Replace('"','')
            # Executa a desinstalação silenciosa
            Start-Process -FilePath $uninstallPath -ArgumentList "/S" -Wait -ErrorAction SilentlyContinue
        }
    }
}
Write-Host "Processo TeamViewer concluído!" -ForegroundColor Green
