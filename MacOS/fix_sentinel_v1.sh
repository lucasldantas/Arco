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
echo -e "           SENTINELONE - MAC FIX $TARGET_VERSION"
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
status "${WHITE}[2/4] Preparando instalador...${NC}"
DATE=$(date '+%y%m%d%H%M')
TEMP_DIR="/tmp/S1-$DATE"
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

# Token para o instalador
echo "$SITE_TOKEN" > "/tmp/com.sentinelone.registration-token"

if ! curl -L --fail -o "$FILENAME" "$INSTALL_URL"; then
    status "${RED}❌ Erro no download.${NC}"
    exit 1
fi

# --- 3. EXECUÇÃO ---
status "${WHITE}[3/4] Aplicando instalação/upgrade...${NC}"

if [ "$IS_UPGRADE" = true ]; then
    status "Executando upgrade via sentinelctl..."
    # Tenta o upgrade oficial
    if ! sudo "$SCTL" upgrade-pkg "$FILENAME"; then
        status "${YELLOW}Upgrade-pkg falhou ou bloqueado. Tentando installer padrão...${NC}"
        sudo /usr/sbin/installer -pkg "$FILENAME" -target / || true
    fi
else
    status "Executando instalação limpa..."
    sudo /usr/sbin/installer -pkg "$FILENAME" -target /
fi

status "Aguardando inicialização (30s)..."
sleep 30

# --- 4. VALIDAÇÃO E CORREÇÃO DE COMANDOS ---
status "${WHITE}[4/4] Validação Final${NC}"

if [[ -f "$SCTL" ]]; then
    FINAL_OP=$($SCTL status | grep -i "Agent is operational" || true)
    
    if [[ -z "$FINAL_OP" ]]; then
        status "Agente não operacional. Forçando ativação..."
        # Sintaxe corrigida para versões novas (v23+)
        sudo "$SCTL" management token set "$SITE_TOKEN" || sudo "$SCTL" set registration-token "$SITE_TOKEN" || true
        
        status "Recarregando componentes..."
        sudo "$SCTL" unprotect || true # Tenta desproteger caso esteja travado
        sudo "$SCTL" load -v || true
        sleep 10
    fi

    # Verificação Final após tentativa de correção
    if $SCTL status | grep -i "Agent is operational" > /dev/null; then
        echo -e "${GREEN}RESULTADO: SUCESSO. Agente operacional.${NC}"
    else
        echo -e "${RED}RESULTADO: ATENÇÃO. Agente instalado mas requer ativação manual ou via console.${NC}"
        $SCTL status | head -n 5
    fi
fi

rm -f "/tmp/com.sentinelone.registration-token"
