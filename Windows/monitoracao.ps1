# ============================================================
# INVENTÁRIO MASTER - COMPLETO COM LISTA DE PATCHES
# ============================================================

$urlGoogle = "https://script.google.com/macros/s/AKfycbyxTl2QGg6XScSTDkdVOO1N781uKIGrelJCBEKDVOf8wZwFV635BV_NeFn8G0SAOdSi/exec"

function Get-SafeValue {
    param($Value, [string]$Default = "N/A")
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace($Value)) { return $Default }
    return ([string]$Value).Trim()
}

function Get-FolderSizeGB {
    param([string]$Path)
    if (Test-Path $Path) {
        try {
            $size = (Get-ChildItem $Path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            if ($size) { return [math]::Round($size / 1GB, 2) } else { return 0 }
        } catch { return 0 }
    }
    return 0
}

Write-Host "Iniciando coleta completa de dados..." -ForegroundColor Cyan

# 1. USUÁRIO E EXPIRAÇÃO DE SENHA
try {
    $explorer = Get-CimInstance -ClassName Win32_Process -Filter "Name='explorer.exe'" | 
                Invoke-CimMethod -MethodName GetOwner -ErrorAction SilentlyContinue | Select-Object -First 1
    $lastLoggedUser = if ($explorer.User) { $explorer.User } else { "N/A" }

    if ($lastLoggedUser -ne "N/A") {
        $netRaw = net user $lastLoggedUser
        $dateLine = $netRaw | Where-Object { $_ -match '\d{1,2}/\d{1,2}/\d{2,4}' } | Select-Object -First 1
        if ($dateLine -match '(\d{1,2}/\d{1,2}/\d{2,4}\s+\d{1,2}:\d{2}:\d{2})') {
            $passwordExpiration = [DateTime]::Parse($matches[1]).AddDays(90).ToString("dd/MM/yyyy")
        } else { $passwordExpiration = "N/A" }
    } else { $passwordExpiration = "N/A" }
} catch { $lastLoggedUser = "Erro"; $passwordExpiration = "Erro" }

# 2. SISTEMA, VERSÃO E UPTIME
try {
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    $winProductName = Get-SafeValue $osInfo.Caption
    $uptimeSpan = (Get-Date) - $osInfo.LastBootUpTime
    $uptimeHours = [math]::Round($uptimeSpan.TotalHours, 2)
    $cv = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    $winRelease = "$($cv.DisplayVersion) (Build $($cv.CurrentBuild).$($cv.UBR))"
} catch { $winProductName = "N/A"; $uptimeHours = 0; $winRelease = "N/A" }

# 3. HARDWARE BASE E BATERIA
try { $serialNumber = Get-SafeValue (Get-CimInstance Win32_BIOS).SerialNumber } catch { $serialNumber = "N/A" }
try {
    $cs = Get-CimInstance Win32_ComputerSystem
    $manufacturer = Get-SafeValue $cs.Manufacturer
    $model = Get-SafeValue $cs.Model
} catch { $manufacturer = "N/A"; $model = "N/A" }

$designCap = "N/A"; $fullCap = "N/A"; $saudePerc = "N/A"
try {
    $batteryStatic = Get-WmiObject -Namespace root\wmi -Class BatteryStaticData -ErrorAction SilentlyContinue
    $batteryFull   = Get-WmiObject -Namespace root\wmi -Class BatteryFullChargedCapacity -ErrorAction SilentlyContinue
    if ($batteryStatic -and $batteryFull) {
        $designCap = $batteryStatic.DesignedCapacity
        $fullCap   = $batteryFull.FullChargedCapacity
        $saudePerc = "$([math]::Round(($designCap / $fullCap) * 100, 2))%"
    }
} catch { }

try {
    $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
    $batteryCharge = if ($battery) { [int]$battery.EstimatedChargeRemaining } else { 0 }
    $bitlocker = Get-BitLockerVolume -MountPoint "C:" -ErrorAction SilentlyContinue
    $bitlockerStatus = Get-SafeValue $bitlocker.VolumeStatus "Unknown"
} catch { $batteryCharge = 0; $bitlockerStatus = "Unknown" }

# 4. PROCESSADOR E TEMPERATURA
try {
    $cpuInfo = Get-CimInstance Win32_Processor
    $cpuNome = Get-SafeValue $cpuInfo.Name
    $cpuUso = [int]($cpuInfo | Measure-Object -Property LoadPercentage -Average).Average

    $tempData = Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue
    if ($tempData) {
        $maxTempRaw = ($tempData | Measure-Object -Property CurrentTemperature -Maximum).Maximum
        $cpuTemp = "$([math]::Round(($maxTempRaw / 10) - 273.15, 2)) °C"
    } else { $cpuTemp = "N/A (Requer Admin)" }
} catch { $cpuNome = "N/A"; $cpuUso = 0; $cpuTemp = "N/A" }

# 5. OPÇÃO DE ENERGIA
try {
    $pwrScheme = powercfg /getactivescheme
    if ($pwrScheme -match '\(([^)]+)\)') { $planoEnergia = $matches[1] } else { $planoEnergia = "Desconhecido" }
} catch { $planoEnergia = "Erro" }

# 6. PERFORMANCE, REDE E GEO
try {
    $ramTotal = [math]::Round(($osInfo.TotalVisibleMemorySize / 1MB), 2)
    $ramFree = [math]::Round(($osInfo.FreePhysicalMemory / 1MB), 2)
    $ramUsageGb = [math]::Round(($ramTotal - $ramFree), 2)
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $diskTotal = [math]::Round($disk.Size / 1GB, 2)
    $diskFree = [math]::Round($disk.FreeSpace / 1GB, 2)
    
    $localIp = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "169.*" -and $_.InterfaceAlias -notlike "*Loopback*" } | Sort-Object InterfaceMetric | Select-Object -First 1).IPAddress
    $ssidLine = netsh wlan show interfaces | Where-Object { $_ -match '^\s*SSID\s*:\s*(.+)$' }
    $wifiSsid = if ($ssidLine) { ($ssidLine -split ":")[1].Trim() } else { "Cabeada" }
    $pingGoogle = [int]((Test-Connection "8.8.8.8" -Count 1 -ErrorAction SilentlyContinue).ResponseTime | Measure-Object -Average).Average
} catch { $ramUsageGb = 0; $diskFree = 0; $localIp = "N/A"; $pingGoogle = 0 }

$publicIp = "N/A"; $city = "N/A"; $isp = "N/A"
try {
    $geo = Invoke-RestMethod -Uri "https://ipapi.co/json/" -TimeoutSec 5
    $publicIp = $geo.ip; $city = $geo.city; $isp = $geo.org
} catch { }

# 7. AGENTES E BUSCA DETALHADA DE PATCHES
$zscaler = if(Get-Process "ZSAI" -ErrorAction SilentlyContinue){"Sim"}else{"Não"}
$sentinel = if(Get-Service "SentinelAgent" -ErrorAction SilentlyContinue){"Sim"}else{"Não"}
$jcAgent = if(Test-Path "C:\Program Files\JumpCloud"){"Sim"}else{"Não"}

try {
    # Busca de Patches Detalhada
    $updateSearcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
    $searchResult = $updateSearcher.Search("IsInstalled=0")
    if ($searchResult.Updates.Count -gt 0) {
        $patchesPendentes = ($searchResult.Updates | ForEach-Object { $_.Title }) -join "; "
    } else {
        $patchesPendentes = "Não"
    }

    # Programas Instalados
    $regPaths = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*")
    $programasFormatados = (Get-ItemProperty $regPaths -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -ne $null } | ForEach-Object { "$($_.DisplayName)" } | Sort-Object -Unique) -join "; "
} catch { $programasFormatados = "Erro"; $patchesPendentes = "Erro na Busca" }

# 8. TAMANHO DE PASTAS
Write-Host "Calculando pastas temporárias e cache..." -ForegroundColor Yellow
$tempSistema = Get-FolderSizeGB "C:\Windows\Temp"
$tempUsuario = Get-FolderSizeGB "$env:LOCALAPPDATA\Temp"
$cacheChrome = Get-FolderSizeGB "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"
$cacheEdge   = Get-FolderSizeGB "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"

# =========================
# 9. PAYLOAD FINAL ORGANIZADO
# =========================
$payload = [ordered]@{
    # IDENTIFICAÇÃO
    Data_Hora               = (Get-Date -Format "dd/MM/yyyy HH:mm:ss")
    Hostname                = $env:COMPUTERNAME
    Usuario                 = $lastLoggedUser
    Senha_Expira            = $passwordExpiration
    Serial                  = $serialNumber
    Fabricante              = $manufacturer
    Modelo                  = $model

    # PERFORMANCE / ENERGIA / TÉRMICO
    CPU_Modelo              = $cpuNome
    CPU_Temp                = $cpuTemp
    CPU_Uso                 = "$cpuUso%"
    RAM_Total_GB            = $ramTotal
    RAM_Uso_GB              = $ramUsageGb
    Plano_Energia           = $planoEnergia
    Bateria_Perc            = "$batteryCharge%"
    Bateria_Saude           = $saudePerc
    Uptime_Horas            = $uptimeHours

    # ARMAZENAMENTO E LIMPEZA
    Disco_Total_GB          = $diskTotal
    Disco_Livre_GB          = $diskFree
    Temp_Sistema_GB         = $tempSistema
    Temp_Usuario_GB         = $tempUsuario
    Cache_Chrome_GB         = $cacheChrome
    Cache_Edge_GB           = $cacheEdge

    # CONECTIVIDADE E LOCALIZAÇÃO
    IP_Local                = $localIp
    IP_Publico              = $publicIp
    Cidade                  = $city
    Provedor_Internet       = $isp
    WiFi_SSID               = $wifiSsid
    Latencia_ms             = $pingGoogle

    # SEGURANÇA E STATUS
    Bitlocker               = $bitlockerStatus
    Zscaler                 = $zscaler
    SentinelOne             = $sentinel
    JumpCloud               = $jcAgent
    Patches_Pendentes       = $patchesPendentes

    # INFOS DO SISTEMA
    Windows                 = $winProductName
    Build                   = $winRelease
    Programas_Instalados    = $programasFormatados
}

$jsonBody = $payload | ConvertTo-Json -Depth 5 -Compress

try {
    Invoke-RestMethod -Uri $urlGoogle -Method Post -Body $jsonBody -ContentType "application/json; charset=utf-8" -ErrorAction Stop
    Write-Host "`n✔ Inventário Completo Enviado com Patches Detalhados!" -ForegroundColor Green
} catch {
    Write-Host "❌ Erro: $($_.Exception.Message)" -ForegroundColor Red
}
