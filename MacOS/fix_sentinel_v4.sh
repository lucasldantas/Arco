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

status "--- [1/4] Verificando integridade ---"

if [[ ! -f "$ctlPath" ]]; then
    status ">> STATUS: Sentinel não encontrado."
    needsUpdate=true
else
    # Captura versão atual (limpa apenas o número)
    currentVersion=$(sudo "$ctlPath" version | awk '{print $2}' | tr -d ',')
    status ">> Versão detectada: $currentVersion"

    # Verifica status (vê se o agente está "running")
    agentStatus=$(sudo "$ctlPath" status)
    
    if [[ "$currentVersion" < "$targetVersion" ]]; then
        status ">> STATUS: Versão desatualizada."
        needsUpdate=true
    elif [[ "$agentStatus" != *"Agent is running"* ]]; then
        status ">> STATUS: Agente parado ou com falha."
        needsFix=true
    else
        status ">> STATUS: SentinelOne íntegro. ✅"
    fi
fi

# --- 2. EXECUÇÃO DA INSTALAÇÃO/ATUALIZAÇÃO ---
if [ "$needsUpdate" = true ]; then
    status "--- [2/4] Iniciando Instalação ---"
    TempFolder="S1-Download-$(date +%s)"
    mkdir -p "/tmp/$TempFolder"
    cd "/tmp/$TempFolder"

    status "Baixando instalador..."
    curl -L --fail --silent -o "$filename" "$DownloadURL"

    # Método de token via arquivo para nova instalação
    echo "$sentinelToken" > "com.sentinelone.registration-token"
    
    status "Instalando..."
    if sudo /usr/sbin/installer -pkg "$filename" -target /; then
        status "✅ Instalado. Aguardando 15s..."
        sleep 15
        needsFix=true
    else
        status "❌ Falha na instalação."
        exit 1
    fi
fi

# --- 3. APLICAÇÃO DOS FIXES (BIND / RESTART) ---
if [ "$needsFix" = true ]; then
    status "--- [3/4] Aplicando reparos ---"
    
    # No Mac, o comando de configuração de token é via 'config'
    status "-> Configurando Token de Registro..."
    sudo "$ctlPath" config registration_token "$sentinelToken" || true
    
    # Reiniciar o agente para forçar a comunicação
    status "-> Reiniciando o agente..."
    sudo "$ctlPath" restart || true
    
    sleep 5
fi

# --- 4. VALIDAÇÃO FINAL ---
status "--- [4/4] Relatório Final ---"
if [[ -f "$ctlPath" ]]; then
    finalStatus=$(sudo "$ctlPath" status)
    if [[ "$finalStatus" == *"Agent is running"* ]]; then
        status "RESULTADO: [SUCESSO] Agente Online. ✅"
    else
        status "RESULTADO: [FALHA] Agente ainda offline. Verifique o console S1."
    fi
fi

# Limpeza silenciosa
[[ -d "/tmp/${TempFolder:-}" ]] && rm -rf "/tmp/$TempFolder"
