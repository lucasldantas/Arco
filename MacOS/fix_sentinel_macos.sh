#!/bin/bash

# --- CONFIGURAÇÕES ---
SITE_TOKEN="eyJ1cmwiOiAiaHR0cHM6Ly91c2VhMS0wMTYuc2VudGluZWxvbmUubmV0IiwgInNpdGVfa2V5IjogIjM2ZWM1YmJmNDVhOTRiZjAifQ=="
INSTALL_URL="https://temp-arco-itops.s3.us-east-1.amazonaws.com/MACOS_Sentinel-Release-25-3-1-8253_macos_v25_3_1_8253.pkg"
TARGET_VERSION="25.3.1.8253"
FILENAME="sentineloneagent.pkg"
SCTL="/usr/local/bin/sentinelctl"

set -euo pipefail

# Cores
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

status() {
    echo -e "${CYAN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

cleanup() {
    if [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        status "Limpeza concluída."
    fi
}
trap cleanup EXIT

clear
echo -e "${CYAN}=========================================================="
echo -e "           SENTINELONE - HOT FIX $TARGET_VERSION"
echo -e "==========================================================${NC}"

# --- 1. VERIFICAÇÃO ---
status "${WHITE}[1/4] Verificando integridade...${NC}"

NEEDS_INSTALL=true
IS_UPGRADE=false

if [[ -f "$SCTL" ]]; then
    CURRENT_VERSION=$($SCTL version | awk '{print $NF}' || echo "0.0.0.0")
    IS_OP=$($SCTL status | grep -i "Agent is operational" || true)

    if [[ "$CURRENT_VERSION" == "$TARGET_VERSION" ]] && [[ -n "$IS_OP" ]]; then
        status "${GREEN}Agente já está na versão $TARGET_VERSION e operacional.${NC}"
        exit 0
    fi
    
    status "Agente detectado ($CURRENT_VERSION). Preparando para Upgrade/Reparo."
    IS_UPGRADE=true
fi

# --- 2. DOWNLOAD ---
status "${WHITE}[2/4] Baixando instalador...${NC}"
DATE=$(date '+%y%m%d%H%M')
TEMP_DIR="/tmp/S1-$DATE"
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

# Token para instalação limpa
echo "$SITE_TOKEN" > "/tmp/com.sentinelone.registration-token"

if ! curl -L --fail -o "$FILENAME" "$INSTALL_URL"; then
    status "${RED}❌ Erro no download.${NC}"
    exit 1
fi

# --- 3. INSTALAÇÃO OU UPGRADE ---
status "${WHITE}[3/4] Iniciando processo de escrita em disco...${NC}"

if [ "$IS_UPGRADE" = true ]; then
    status "Executando upgrade via sentinelctl..."
    # O comando upgrade-pkg é o método oficial para quando o agente já existe
    if sudo "$SCTL" upgrade-pkg "$FILENAME"; then
        status "${GREEN}✅ Comando de upgrade aceito.${NC}"
    else
        status "${RED}❌ Falha no upgrade-pkg. Tentando forçar via installer...${NC}"
        sudo /usr/sbin/installer -pkg "$FILENAME" -target / || true
    fi
else
    status "Executando instalação limpa via installer..."
    sudo /usr/sbin/installer -pkg "$FILENAME" -target /
fi

status "Aguardando estabilização (30s)..."
sleep 30

# --- 4. VALIDAÇÃO ---
status "${WHITE}[4/4] Validação Final${NC}"
if [[ -f "$SCTL" ]]; then
    FINAL_OP=$($SCTL status | grep -i "Agent is operational" || true)
    if [[ -n "$FINAL_OP" ]]; then
        echo -e "${GREEN}RESULTADO: SUCESSO. Agente operacional.${NC}"
    else
        status "Agente não operacional. Tentando bind final..."
        sudo "$SCTL" management token set "$SITE_TOKEN" || true
        sudo "$SCTL" control start || true
        status "Verifique o painel em instantes."
    fi
fi

rm -f "/tmp/com.sentinelone.registration-token"
