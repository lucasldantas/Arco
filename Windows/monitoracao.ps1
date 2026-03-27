# ============================================================
# INVENTÁRIO MASTER - DESTINO: SUPABASE (LOOP DE 1 HORA)
# ============================================================

while($true) {
    # AJUSTE DE CARGA: Evita que 3.000 máquinas enviem dados no mesmo segundo.
    # O script aguardará um tempo aleatório entre 10 e 600 segundos (10 minutos).
    $randomDelay = Get-Random -Minimum 10 -Maximum 600
    Write-Host "Aguardando $randomDelay segundos para balanceamento de carga no Supabase..." -ForegroundColor Yellow
    Start-Sleep -Seconds $randomDelay

    # CONFIGURAÇÕES SUPABASE
    $supabaseUrl = "https://bmwftjnxphmthqglagmf.supabase.co/rest/v1/machine_logs"
    $apiKey      = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJtd2Z0am54cGhtdGhxZ2xhZ21mIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM2Njk5NjcsImV4cCI6MjA4OTI0NTk2N30.MQjlRXhsleLfTXVE2VEqVG1AANg13kFEI4Blc5U1tao"

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

    Write-Host "Iniciando coleta completa de dados para Supabase..." -ForegroundColor Cyan

    # 1. USUÁRIO
    try {
        $explorer = Get-CimInstance -ClassName Win32_Process -Filter "Name='explorer.exe'" | 
                    Invoke-CimMethod -MethodName GetOwner -ErrorAction SilentlyContinue | Select-Object -First 1
        $lastLoggedUser = if ($explorer.User) { $explorer.User } else { "N/A" }
    } catch { $lastLoggedUser = "Erro" }

    # 2. SISTEMA E UPTIME
    try {
        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $winProductName = Get-SafeValue $osInfo.Caption
        $uptimeSpan = (Get-Date) - $osInfo.LastBootUpTime
        $uptimeHours = [math]::Round($uptimeSpan.TotalHours, 2)
        $cv = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
        $winRelease = "$($cv.DisplayVersion) (Build $($cv.CurrentBuild).$($cv.UBR))"
    } catch { $winProductName = "N/A"; $uptimeHours = 0; $winRelease = "N/A" }

    # 3. HARDWARE E BATERIA
    try { $serialNumber = Get-SafeValue (Get-CimInstance Win32_BIOS).SerialNumber } catch { $serialNumber = "N/A" }
    try {
        $cs = Get-CimInstance Win32_ComputerSystem
        $manufacturer = Get-SafeValue $cs.Manufacturer
        $model = Get-SafeValue $cs.Model
    } catch { $manufacturer = "N/A"; $model = "N/A" }

    $saudePerc = "N/A"
    try {
        $batteryStatic = Get-WmiObject -Namespace root\wmi -Class BatteryStaticData -ErrorAction SilentlyContinue
        $batteryFull   = Get-WmiObject -Namespace root\wmi -Class BatteryFullChargedCapacity -ErrorAction SilentlyContinue
        if ($batteryStatic -and $batteryFull) {
            $saudePerc = "$([math]::Round(($batteryStatic.DesignedCapacity / $batteryFull.FullChargedCapacity) * 100, 2))%"
        }
    } catch { }

    try {
        $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
        $batteryCharge = if ($battery) { [int]$battery.EstimatedChargeRemaining } else { 0 }
        $bitlocker = Get-BitLockerVolume -MountPoint "C:" -ErrorAction SilentlyContinue
        $bitlockerStatus = Get-SafeValue $bitlocker.VolumeStatus "Unknown"
    } catch { $batteryCharge = 0; $bitlockerStatus = "Unknown" }

    # 4. PROCESSADOR E TEMP
    try {
        $cpuInfo = Get-CimInstance Win32_Processor
        $cpuNome = Get-SafeValue $cpuInfo.Name
        $cpuUso = [int]($cpuInfo | Measure-Object -Property LoadPercentage -Average).Average
        $tempData = Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue
        if ($tempData) {
            $maxTempRaw = ($tempData | Measure-Object -Property CurrentTemperature -Maximum).Maximum
            $cpuTemp = "$([math]::Round(($maxTempRaw / 10) - 273.15, 2)) °C"
        } else { $cpuTemp = "N/A" }
    } catch { $cpuNome = "N/A"; $cpuUso = 0; $cpuTemp = "N/A" }

    # 5. ENERGIA E PERFORMANCE
    try {
        $pwrScheme = powercfg /getactivescheme
        if ($pwrScheme -match '\(([^)]+)\)') { $planoEnergia = $matches[1] } else { $planoEnergia = "Desconhecido" }
        $ramTotal = [math]::Round(($osInfo.TotalVisibleMemorySize / 1MB), 2)
        $ramFree = [math]::Round(($osInfo.FreePhysicalMemory / 1MB), 2)
        $ramUsageGb = [math]::Round(($ramTotal - $ramFree), 2)
        $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
        $diskTotal = [math]::Round($disk.Size / 1GB, 2)
        $diskFree = [math]::Round($disk.FreeSpace / 1GB, 2)
    } catch { $planoEnergia = "Erro"; $ramUsageGb = 0; $diskFree = 0 }

    # 6. REDE E GEO
    try {
        $localIp = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Get-NetIPAddress | Where-Object AddressFamily -eq "IPv4" | Select-Object -First 1).IPAddress
        if ([string]::IsNullOrWhiteSpace($localIp)) {
            $localIp = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "127*" -and $_.IPAddress -notlike "169*" } | Sort-Object InterfaceMetric | Select-Object -First 1).IPAddress
        }
        $ssidLine = netsh wlan show interfaces | Where-Object { $_ -match '^\s*SSID\s*:\s*(.+)$' }
        $wifiSsid = if ($ssidLine) { ($ssidLine -split ":")[1].Trim() } else { "Cabeada" }
        $ping = Test-Connection "8.8.8.8" -Count 1 -ErrorAction SilentlyContinue
        $pingGoogle = if ($ping) { [string]$ping.ResponseTime } else { "0" }
        $geo = Invoke-RestMethod -Uri "http://ip-api.com/json/" -TimeoutSec 15
        if ($geo.status -eq "success") {
            $publicIp = [string]$geo.query
            $city     = [string]$geo.city
            $isp      = [string]$geo.isp
        } else { throw }
    } catch { 
        $localIp  = if($localIp){$localIp}else{"Desconectado"}
        $publicIp = "Erro API"; $city = "N/A"; $isp = "N/A"; $pingGoogle = "0" 
    }

    # 7. AGENTES E PATCHES
    $zscaler = if(Get-Process "ZSAService" -ErrorAction SilentlyContinue){"Sim"}else{"Não"}
    $sentinel = if(Get-Service "SentinelAgent" -ErrorAction SilentlyContinue){"Sim"}else{"Não"}
    $jcAgent = if(Test-Path "C:\Program Files\JumpCloud"){"Sim"}else{"Não"}

    try {
        $updateSearcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
        $searchResult = $updateSearcher.Search("IsInstalled=0")
        $patchesPendentes = if ($searchResult.Updates.Count -gt 0) { ($searchResult.Updates | ForEach-Object { $_.Title }) -join "; " } else { "Não" }
        $regPaths = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*")
        $programasFormatados = (Get-ItemProperty $regPaths -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -ne $null } | ForEach-Object { "$($_.DisplayName)" } | Sort-Object -Unique) -join "; "
    } catch { $patchesPendentes = "Erro"; $programasFormatados = "Erro" }

    # 8. TAMANHO DE PASTAS
    $tempSistema = Get-FolderSizeGB "C:\Windows\Temp"
    $tempUsuario = Get-FolderSizeGB "$env:LOCALAPPDATA\Temp"
    $cacheChrome = Get-FolderSizeGB "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"
    $cacheEdge   = Get-FolderSizeGB "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"

    # 9. PAYLOAD FINAL
    $payload = @{
        data_hora            = [string](Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        hostname             = [string]$env:COMPUTERNAME
        usuario              = [string]$lastLoggedUser
        serial               = [string]$serialNumber
        fabricante           = [string]$manufacturer
        modelo               = [string]$model
        cpu_modelo           = [string]$cpuNome
        cpu_temp             = [string]$cpuTemp
        cpu_uso              = [string]"$cpuUso"
        ram_total_gb         = [string]$ramTotal
        ram_uso_gb           = [string]$ramUsageGb
        plano_energia        = [string]$planoEnergia
        bateria_perc         = [string]"$batteryCharge%"
        bateria_saude        = [string]$saudePerc
        uptime_horas         = [string]$uptimeHours
        disco_total_gb       = [string]$diskTotal
        disco_livre_gb       = [string]$diskFree
        temp_sistema_gb      = [string]$tempSistema
        temp_usuario_gb      = [string]$tempUsuario
        cache_chrome_gb      = [string]$cacheChrome
        cache_edge_gb        = [string]$cacheEdge
        ip_local             = [string]$localIp
        ip_publico           = [string]$publicIp
        cidade               = [string]$city
        provedor_internet    = [string]$isp
        wifi_ssid            = [string]$wifiSsid
        latencia_ms          = [string]$pingGoogle
        bitlocker            = [string]$bitlockerStatus
        zscaler              = [string]$zscaler
        sentinelone          = [string]$sentinel
        jumpcloud            = [string]$jcAgent
        patches_pendentes    = [string]$patchesPendentes
        windows              = [string]$winProductName
        build                = [string]$winRelease
        programas_instalados = [string]$programasFormatados
    }

    $jsonBody = $payload | ConvertTo-Json -Depth 5 -Compress
    $utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)

    # 10. ENVIO
    $rawUrl = "https://bmwftjnxphmthqglagmf.supabase.co/rest/v1/machine_logs"
    $headers = @{
        "apikey"        = $apiKey
        "Authorization" = "Bearer $apiKey"
        "Content-Type"  = "application/json; charset=utf-8"
        "Prefer"        = "resolution=merge-duplicates"
    }

    try {
        $uriBuilder = New-Object System.UriBuilder($rawUrl)
        $uriBuilder.Query = "on_conflict=hostname"
        $finalUri = $uriBuilder.Uri.AbsoluteUri
        Invoke-RestMethod -Uri $finalUri -Method Post -Body $utf8Bytes -Headers $headers -ErrorAction Stop
        Write-Host "`n✔ Inventário sincronizado!" -ForegroundColor Green
    } catch {
        Write-Host "`n❌ Erro no Envio!" -ForegroundColor Red
    }

    # Aguarda 1 hora (3600 segundos) antes de reiniciar o loop
    Write-Host "Ciclo concluído. Próxima coleta em 60 minutos..." -ForegroundColor Gray
    Start-Sleep -Seconds 3600
}
