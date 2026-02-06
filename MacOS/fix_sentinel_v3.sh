#!/bin/bash

#########################################################
#           SENTINELONE MAC - HEALTH CHECK & FIX        #
#########################################################

sentinelToken="eyJ1cmwiOiAiaHR0cHM6Ly91c2VhMS0wMTYuc2VudGluZWxvbmUubmV0IiwgInNpdGVfa2V5IjogIjM2ZWM1YmJmNDVhOTRiZjAifQ=="
DownloadURL="https://temp-arco-itops.s3.us-east-1.amazonaws.com/MACOS_Sentinel-Release-25-3-1-8253_macos_v25_3_1_8253.pkg"
targetVersion="25.3.1.8253"
filename="sentineloneagent.pkg"
ctlPath="/usr/local/bin/sentinelctl"

set -euo pipefail

status() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# --- 1. VERIFICAÇÃO DE SAÚDE ---
needsUpdate=false
needsFix=false

status "--- [1/4] Verificando integridade do sistema ---"

if [[ ! -f "$ctlPath" ]]; then
    status ">> STATUS: Sentinel não encontrado ou sentinelctl ausente."
    needsUpdate=true
else
    # Captura versão atual
    currentVersion=$(sudo "$ctlPath" version | awk '{print $2}')
    status ">> Versão detectada: $currentVersion"

    # Captura status dos serviços
    agentStatus=$(sudo "$ctlPath" status)
    
    # Verifica se a versão é inferior à meta
    if [[ "$currentVersion" < "$targetVersion" ]]; then
        status ">> STATUS: Versão desatualizada."
        needsUpdate=true
    # Verifica se os daemons estão rodando (equivalente ao Monitor/Agent do Windows)
    elif [[ "$agentStatus" != *"SentinelAgent is running"* ]]; then
        status ">> STATUS: Componentes offline ou descarregados."
        needsFix=true
    else
        status ">> STATUS: SentinelOne está íntegro e atualizado. ✅"
    fi
fi

# --- 2. EXECUÇÃO DA INSTALAÇÃO/ATUALIZAÇÃO ---
if [ "$needsUpdate" = true ]; then
    status "--- [2/4] Iniciando Download e Instalação ---"
    TempFolder="S1-Install-$(date +%s)"
    mkdir -p "/tmp/$TempFolder"
    cd "/tmp/$TempFolder"

    status "Baixando instalador..."
    curl -L --fail --silent -o "$filename" "$DownloadURL"

    # Cria token para a instalação
    echo "$sentinelToken" > "com.sentinelone.registration-token"
    
    status "Executando instalador silencioso..."
    if sudo /usr/sbin/installer -pkg "$filename" -target /; then
        status "✅ Instalação concluída. Aguardando inicialização..."
        sleep 15
        needsFix=true
    else
        status "❌ Falha crítica na instalação."
        exit 1
    fi
else
    status "--- [2/4] Atualização não necessária. ---"
fi

# --- 3. APLICAÇÃO DOS FIXES (BIND / RELOAD) ---
if [ "$needsFix" = true ]; then
    status "--- [3/4] Aplicando comandos de reparo e vinculação ---"
    
    # Tenta vincular o token (Bind)
    status "-> Vinculando Token de Site..."
    sudo "$ctlPath" management token set "$sentinelToken" || true
    
    # Reload dos serviços
    status "-> Reiniciando daemons do agente..."
    sudo "$ctlPath" unload || true
    sleep 2
    sudo "$ctlPath" load || true
    
    status "Comandos de reparo enviados."
fi

# --- 4. VALIDAÇÃO FINAL ---
status "--- [4/4] Relatório Final de Operação ---"
if [[ -f "$ctlPath" ]]; then
    finalStatus=$(sudo "$ctlPath" status)
    if [[ "$finalStatus" == *"SentinelAgent is running"* ]]; then
        status "RESULTADO: [SUCESSO] Agente Online e Operacional no macOS. ✅"
    else
        status "RESULTADO: [FALHA] Agente ainda apresenta problemas. Verifique manualmente."
    fi
else
    status "RESULTADO: [ERRO] Binários não encontrados após execução."
fi

# Limpeza
[[ -d "/tmp/$TempFolder" ]] && rm -rf "/tmp/$TempFolder"
