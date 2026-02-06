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
    fi
    rm -f "/tmp/com.sentinelone.registration-token"
    rm -f "/tmp/s1_token.txt"
    status "Limpeza de arquivos temporários concluída."
}
trap cleanup EXIT

clear
echo -e "${CYAN}=========================================================="
echo -e "           SENTINELONE - MAC FIX $TARGET_VERSION"
echo -e "==========================================================${NC}"

# --- 1. VERIFICAÇÃO ---
status "${WHITE}[1/4] Verificando estado atual...${NC}"

IS_UPGRADE=false

if [[ -f "$SCTL" ]]; then
    CURRENT_VERSION=$($SCTL version | awk '{print $NF}' || echo "0.0.0.0")
    IS_OP=$($SCTL status | grep -i "Agent is operational" || true)

    if [[ "$CURRENT_VERSION" == "$TARGET_VERSION" ]] && [[ -n "$IS_OP" ]]; then
        status "${GREEN}Agente SentinelOne já está na versão $TARGET_VERSION e operacional.${NC}"
        exit 0
    fi
    
    status "Agente detectado ($CURRENT_VERSION). Preparando upgrade/reparo..."
    IS_UPGRADE=true
fi

# --- 2. DOWNLOAD E PREPARAÇÃO ---
status "${WHITE}[2/4] Preparando instalador...${NC}"
TEMP_DIR="/tmp/S1_FIX_$(date '+%H%M%S')"
mkdir -p "$TEMP_DIR"

# Criar arquivo de token (Versão 25.x exige arquivo para o comando 'set registration-token-file')
echo "$SITE_TOKEN" > "/tmp/com.sentinelone.registration-token"
echo "$SITE_TOKEN" > "/tmp/s1_token.txt"

if ! curl -L --fail -o "$TEMP_DIR/$FILENAME" "$INSTALL_URL"; then
    status "${RED}❌ Falha ao baixar o instalador.${NC}"
    exit 1
fi

# --- 3. INSTALAÇÃO / UPGRADE ---
status "${WHITE}[3/4] Iniciando instalação (isso pode levar alguns minutos)...${NC}"

if [ "$IS_UPGRADE" = true ]; then
    # Tenta o upgrade oficial via binário primeiro
    if ! sudo "$SCTL" upgrade-pkg "$TEMP_DIR/$FILENAME"; then
        status "Upgrade-pkg falhou (possível Anti-Tamper). Tentando via installer nativo..."
        sudo /usr/sbin/installer -pkg "$TEMP_DIR/$FILENAME" -target / || true
    fi
else
    # Instalação limpa
    sudo /usr/sbin/installer -pkg "$TEMP_DIR/$FILENAME" -target /
fi

status "Aguardando estabilização do sistema (30s)..."
sleep 30

# --- 4. VALIDAÇÃO E ATIVAÇÃO ---
status "${WHITE}[4/4] Validação Final${NC}"

if [[ -f "$SCTL" ]]; then
    FINAL_OP=$($SCTL status | grep -i "Agent is operational" || true)
    
    if [[ -z "$FINAL_OP" ]]; then
        status "Agente não operacional. Forçando ativação via token-file..."
        # Sintaxe CORRETA para v25.x: aponta para o ARQUIVO, não para a STRING
        sudo "$SCTL" set registration-token-file "/tmp/s1_token.txt" || true
        
        status "Tentando carregar serviços via launchctl..."
        sudo launchctl load /Library/LaunchDaemons/com.sentinelone.sentinelagent.plist 2>/dev/null || true
        sleep 10
    fi

    # Resultado Final
    if $SCTL status | grep -i "Agent is operational" > /dev/null; then
        echo -e "----------------------------------------------------------"
        echo -e " RESULTADO: ${GREEN}[SUCESSO] Agente Online e Protegido.${NC}"
        echo -e "----------------------------------------------------------"
    else
        echo -e "----------------------------------------------------------"
        echo -e " RESULTADO: ${RED}[ATENÇÃO] Agente instalado ($TARGET_VERSION).${NC}"
        echo -e " Status: Missing Authorizations ou Anti-Tamper Ativo."
        echo -e " Verifique o Full Disk Access e as System Extensions no macOS."
        echo -e "----------------------------------------------------------"
        $SCTL status | head -n 8 || true
    fi
else
    status "${RED}❌ Erro crítico: Binário sentinelctl não encontrado.${NC}"
    exit 1
fi
