# Nomes dos aplicativos para buscar
$apps = @("TeamViewer", "AnyDesk")

Write-Host "Iniciando a busca e remoção de softwares de acesso remoto..." -ForegroundColor Cyan

foreach ($app in $apps) {
    # Busca nos registros de 32 e 64 bits
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($path in $paths) {
        $found = Get-ItemProperty $path | Where-Object { $_.DisplayName -like "*$app*" }

        foreach ($item in $found) {
            $name = $item.DisplayName
            $uninstallString = $item.UninstallString

            if ($uninstallString) {
                Write-Host "Removendo: $name..." -ForegroundColor Yellow

                # Tratamento específico para o AnyDesk (usa --remove)
                if ($name -like "*AnyDesk*") {
                    Start-Process -FilePath "C:\Program Files (x86)\AnyDesk\AnyDesk.exe" -ArgumentList "--remove", "--silent" -Wait -ErrorAction SilentlyContinue
                }
                # Tratamento para TeamViewer (usa /S)
                elseif ($uninstallString -like "*TeamViewer*") {
                    $uninstallPath = $uninstallString.Replace('"','')
                    Start-Process -FilePath $uninstallPath -ArgumentList "/S" -Wait -ErrorAction SilentlyContinue
                }
            }
        }
    }
}

Write-Host "Processo concluído!" -ForegroundColor Green
