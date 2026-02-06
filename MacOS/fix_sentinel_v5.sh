#!/bin/bash

#########################################################
#           SENTINELONE MAC - HEALTH CHECK & FIX        #
#########################################################

sentinelToken="eyJ1cmwiOiAiaHR0cHM6Ly91c2VhMS0wMTYuc2VudGluZWxvbmUubmV0IiwgInNpdGVfa2V5IjogIjM2ZWM1YmJmNDVhOTRiZjAifQ=="
DownloadURL="https://temp-arco-itops.s3.us-east-1.amazonaws.com/MACOS_Sentinel-Release-25-3-1-8253_macos_v25_3_1_8253.pkg"
targetVersion="25.3.1.8253"
filename="sentineloneagent.pkg"
ctlPath="/usr/local/bin/sentinelctl"

# set -u removido para evitar erro de 'unbound variable' em variáveis opcionais
set -eo pipefail

status() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# --- 1. VERIFICAÇÃO DE SAÚDE ---
needsUpdate=false
needsFix=false

status "--- [1/4] Verificando integridade ---"

if [[ ! -f "$ctlPath" ]]; then
    status ">> STATUS: Sentinel não encontrado no sistema."
    needsUpdate=true
else
    # Captura versão e limpa caracteres extras
    currentVersion=$(sudo "$ctlPath" version | awk '{print $2}' | tr -d ',')
    status ">> Versão instalada: $currentVersion"

    # Verifica status do agente
    agentStatus=$(sudo "$ctlPath" status)
    
    if [[ "$currentVersion" < "$targetVersion" ]]; then
        status ">> STATUS: Versão inferior à meta ($targetVersion)."
        needsUpdate=true
    elif [[ "$agentStatus" != *"Agent is running"* ]]; then
        status ">> STATUS: Agente não está rodando (está parado ou com falha)."
        needsFix=true
    else
        status ">> STATUS: SentinelOne já está funcional e atualizado. ✅"
    fi
fi

# --- 2. EXECUÇÃO DA INSTALAÇÃO/ATUALIZAÇÃO ---
if [ "$needsUpdate" = true ]; then
    status "--- [2/4] Iniciando Processo de Instalação ---"
    TempFolder="S1-Download-$(date +%s)"
    mkdir -p "/tmp/$TempFolder"
    cd "/tmp/$TempFolder"

    status "Baixando instalador via curl..."
    if curl -L --fail --silent -o "$filename" "$DownloadURL"; then
        # Cria arquivo de token para o instalador PKG ler durante a instalação
        echo "$sentinelToken" > "com.sentinelone.registration-token"
        
        status "Executando instalador oficial..."
        if sudo /usr/sbin/installer -pkg "$filename" -target /; then
            status "✅ Instalação concluída. Aguardando inicialização dos serviços..."
            sleep 15
            needsFix=true
        else
            status "❌ Erro ao executar o comando installer."
            exit 1
        fi
    else
        status "❌ Falha ao baixar o arquivo da URL fornecida."
        exit 1
    fi
fi

# --- 3. APLICAÇÃO DOS FIXES (REPARAÇÃO DE COMUNICAÇÃO) ---
if [ "$needsFix" = true ]; then
    status "--- [3/4] Aplicando comandos de reparo e bind ---"
    
    # Comandos baseados no seu help: 'set' para configurar e 'restart' para recarregar
    status "-> Vinculando Site Token..."
    sudo "$ctlPath" set registration_token "$sentinelToken" || status "Aviso: Falha ao setar token (pode já estar configurado)."
    
    status "-> Reiniciando o Agente..."
    sudo "$ctlPath" restart || status "Aviso: Falha ao reiniciar (tentando 'start')."
    sudo "$ctlPath" start 2>/dev/null || true
    
    status "Comandos de reparo executados."
    sleep 5
fi

# --- 4. VALIDAÇÃO FINAL ---
status "--- [4/4] Relatório Final de Operação ---"
if [[ -f "$ctlPath" ]]; then
    finalStatus=$(sudo "$ctlPath" status)
    if [[ "$finalStatus" == *"Agent is running"* ]]; then
        status "RESULTADO: [SUCESSO] Agente Online e Protegido. ✅"
    else
        status "RESULTADO: [FALHA] Agente instalado, mas não reporta 'running'."
        status "Status atual: $finalStatus"
    fi
else
    status "RESULTADO: [ERRO] Binários não encontrados após a execução."
fi

# Limpeza da pasta temporária se ela existir
if [[ -n "${TempFolder:-}" && -d "/tmp/$TempFolder" ]]; then
    rm -rf "/tmp/$TempFolder"
fi
