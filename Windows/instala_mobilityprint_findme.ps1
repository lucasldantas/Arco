################## INSTALA O MOBILITYPRINT E REMOVE IMPRESSORAS ESPECÍFICAS ##################

$MobilityPrintClientUrl = "https://cdn.papercut.com/web/products/mobility-print/installers/client/windows-cloud/mobility-print-client-installer-1.0.691.msi"
$InstallerName = "mobility-print-client-installer-1.0.691.msi"
$DownloadPath = "$env:TEMP\$InstallerName"
$MobilityPrintBaseDir = "C:\Program Files\PaperCut Mobility Print Client"
$CloudConfigUrl = "https://mp.cloud.papercut.com/?token=eyJhbGciOiJSUzI1NiIsIm9yZyI6Im9yZy1DMUNCVE04NiIsInNydiI6InNydi1OWU1aUVk2RiIsInR5cCI6IkpXVCJ9.eyJpYXQiOjE3NjQwMzg3NDcsImlzcyI6InNydi1OWU1aUVk2RiIsImp0aSI6IjhUTjdDSzhZIiwibG5rIjoiOFRON0NLOFkiLCJvcmciOiJvcmctQzFDQlRNODYiLCJzcnYiOiJzcnYtTllNWlFZNkYiLCJzdWIiOiJ0b2tlbkNyZWF0aW9uIn0.itDFtOvuy1b2xpaRosrzNPrPs7EY-YOdCpdzX-VqXNhoxUaC486WU7g0x5aZCU6WCqIBP_hnUDi7yVvelmMLBD78sawBoj_1mH_rVdtWEKi_njTZOei85X7tmK4ZUYhgbExBamQ1MAIrjGRQczExBqtIk8vY09Vh5SxZ9CjDV-jlPdFBAPPdCq6xkPIzb_rjWmskwoGk7aIP4c33qitO-FAInam42-sKGH-ShIsUfbdaz9Q3nO2kVU0A-ruevoAx_Zrs-Tz3pKPHte09cHxJV8VN-iZwIO313G4JxpgSctNAapOAOqBpZBKsh40pUz0aygp-sh5_1aYgOrrwsJxQkytxTI3gMJZliunZsudmv3WT1ae4dlwpiZrUTPDF-6Z5lGG8dsNeRrVTWWHK0OGqFI4Z5c1OWaEE6f9-UWqeNRSgD82jVwh5QoQv4AY2S1uKybrdYP0MkoI8yvixUWk_Dp2oE4z8GOGB3DR6kDda6HmLFJWjTgNQrRtuiXP-sg5aJvN6cSRZadEQpjH28aFY95yBtY7C7SwwcNcwxg5HfbkxUgazPiEmoGR9W6MWUsu6k9crd6iG0wKRWxIxMHDk-UDWBNkbVjDi5ryku_pM-Sn6gwmLPXl-GAI6arKv6510Q1UVK7KdoXC58ubIManafU5LL-YIVj1dgUO436cLsdM"
$Installed = $false

# ----------------------------------------
# FUNÇÃO: INSTALAÇÃO
# ----------------------------------------
function CheckAndInstall {
    param([string]$Url, [string]$Installer, [string]$Path)
    Write-Host "STATUS: Verificando instalação do Mobility Print..." -ForegroundColor Cyan
    try {
        $App = Get-ChildItem -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\' | Get-ItemProperty | Where-Object { $_.DisplayName -like 'PaperCut Mobility Print Client*' }
        if ($App) {
            $global:Installed = $true
            Write-Host "SUCESSO: MobilityPrint encontrado (Versão: $($App.DisplayVersion))." -ForegroundColor Green
            return
        }
    } catch {
        Write-Host "ERRO: Falha ao verificar registro. Tentando instalar." -ForegroundColor Red
    }

    try {
        Invoke-WebRequest -Uri $Url -OutFile $Path -UseBasicParsing
        $Process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$Path`" /qn /norestart" -Wait -Passthru
        if ($Process.ExitCode -eq 0) {
            Write-Host "SUCESSO: Instalação concluída." -ForegroundColor Green
            $global:Installed = $true
        }
    } catch {
        Write-Error "ERRO FATAL: $($_.Exception.Message)"
    } finally {
        if (Test-Path $Path) { Remove-Item $Path -Force }
    }
}

# ----------------------------------------
# FUNÇÃO: CONFIGURAÇÃO
# ----------------------------------------
function ConfigureClient {
    param([string]$BaseDir, [string]$Url)
    $VersionFolders = Get-ChildItem -Path $BaseDir -Directory | Sort-Object Name -Descending
    if (-not $VersionFolders) { return $false }

    $LatestVersionDir = $VersionFolders[0].FullName
    $ExecutablePath = Join-Path -Path $LatestVersionDir -ChildPath "mobility-print-client.exe"
    $Arguments = "-url `"$Url`""
    
    try {
        Start-Process -FilePath $ExecutablePath -ArgumentList $Arguments -WindowStyle Hidden
        Write-Host "SUCESSO: Comando de configuração enviado." -ForegroundColor Green
        return $true
    } catch {
        return $false
    }
}

# ----------------------------------------
# FUNÇÃO: REMOVER LISTA ESPECÍFICA (NOVA)
# ----------------------------------------
function RemoveSpecificPrinters {
    $TargetPrinters = @(
        "PRINT-ARCO-FOR-BLACK",
        "PRINT-ARCO-FOR-COLOR",
        "PRINT-ARCO-SC-BLACK",
        "PRINT-HUB-BLACK",
        "PRINT-HUB-BLACK-3ANDAR",
        "PRINT-HUB-BLACK-TERREO",
        "PRINT-HUB-COLOR (virtual)",
        "PRINT-HUB-COLOR-2ANDAR",
        "PRINT-ARCO-SP-10º_ANDAR",
        "PRINT-ARCO-DIR-SP",
        "PRINT-ARCO-SP-BLACK",
        "PRINT-ARCO-SP-COLOR"
    )

    Write-Host "STATUS: Iniciando remoção da lista de impressoras legadas..." -ForegroundColor Cyan

    foreach ($Name in $TargetPrinters) {
        $Printer = Get-Printer -Name $Name -ErrorAction SilentlyContinue
        if ($Printer) {
            Write-Host "REMOVENDO: $Name" -ForegroundColor Red
            try {
                Remove-Printer -Name $Name -ErrorAction SilentlyContinue
                # Backup via CIM caso o primeiro falhe (comum em impressoras de rede)
                Get-CimInstance -ClassName Win32_Printer -Filter "Name = '$($Name.Replace("'", "''"))'" | Remove-CimInstance -ErrorAction SilentlyContinue
            } catch {
                Write-Host "Não foi possível remover totalmente $Name (pode ser mapeamento de usuário)." -ForegroundColor Red
            }
        }
    }
}

# ----------------------------------------
# FUNÇÃO: VALIDAR
# ----------------------------------------
function ValidatePrinterInstallation {
    param([string]$ExpectedPrinterPattern = "PRINT-ARCO-FINDME*")
    Write-Host "STATUS: Aguardando detecção da impressora PRINT-ARCO-FINDME (30s)..." -ForegroundColor Cyan
    Start-Sleep -Seconds 30
    
    $Printer = Get-Printer -Name $ExpectedPrinterPattern -ErrorAction SilentlyContinue
    if ($Printer) {
        Write-Host "SUCESSO: Impressora PRINT-ARCO-FINDME detectada!" -ForegroundColor Green
        return $true
    } else {
        Write-Host "AVISO: Impressora PRINT-ARCO-FINDME ainda não apareceu na sessão." -ForegroundColor Yellow
        return $false
    }
}

# ----------------------------------------
# EXECUÇÃO PRINCIPAL
# ----------------------------------------

CheckAndInstall -Url $MobilityPrintClientUrl -Installer $InstallerName -Path $DownloadPath

if ($Installed) {
    Start-Sleep -Seconds 10
    $ConfigSuccess = ConfigureClient -BaseDir $MobilityPrintBaseDir -Url $CloudConfigUrl
    
    if ($ConfigSuccess) {
        $ValidationSuccess = ValidatePrinterInstallation
        
        if ($ValidationSuccess) {
            RemoveSpecificPrinters
            Write-Host "PROCESSO FINALIZADO: PRINT-ARCO-FINDME instalada e impressoras legadas removidas." -ForegroundColor Green
        } else {
            Write-Host "INFO: PRINT-ARCO-FINDME não detectada a tempo. A limpeza foi ignorada para evitar que o usuário fique sem impressora." -ForegroundColor Yellow
        }
    }
}
