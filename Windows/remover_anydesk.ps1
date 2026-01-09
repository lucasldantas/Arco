# Busca e remoção exclusiva do AnyDesk
$app = "AnyDesk"
Write-Host "Iniciando a busca e remoção do $app..." -ForegroundColor Cyan

$paths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

foreach ($path in $paths) {
    $found = Get-ItemProperty $path | Where-Object { $_.DisplayName -like "*$app*" }

    foreach ($item in $found) {
        Write-Host "Removendo: $($item.DisplayName)..." -ForegroundColor Yellow
        # Tenta o caminho padrão de instalação silenciosa
        if (Test-Path "C:\Program Files (x86)\AnyDesk\AnyDesk.exe") {
            Start-Process -FilePath "C:\Program Files (x86)\AnyDesk\AnyDesk.exe" -ArgumentList "--remove", "--silent" -Wait -ErrorAction SilentlyContinue
        } else {
            # Caso não esteja no caminho padrão, tenta usar o UninstallString se disponível
            $uninstallPath = $item.UninstallString.Replace('"','')
            Start-Process -FilePath $uninstallPath -ArgumentList "--remove", "--silent" -Wait -ErrorAction SilentlyContinue
        }
    }
}
Write-Host "Processo AnyDesk concluído!" -ForegroundColor Green
