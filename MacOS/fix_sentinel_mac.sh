#!/bin/bash

# --- CONFIGURAÇÕES ---
SITE_TOKEN="eyJ1cmwiOiAiaHR0cHM6Ly91c2VhMS0wMTYuc2VudGluZWxvbmUubmV0IiwgInNpdGVfa2V5IjogIjM2ZWM1YmJmNDVhOTRiZjAifQ=="
INSTALL_URL="https://temp-arco-itops.s3.us-east-1.amazonaws.com/MACOS_Sentinel-Release-25-3-1-8253_macos_v25_3_1_8253.pkg"
TARGET_VERSION="25.3.1.8253"
FILENAME="sentineloneagent.pkg"
SCTL="/usr/local/bin/sentinelctl"

set -euo pipefail

# Cores para o output
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
        status "Limpeza de arquivos temporários concluída."
    fi
}
trap cleanup EXIT

clear
echo -e "${CYAN}=========================================================="
echo -e "           SENTINELONE - HOT FIX $TARGET_VERSION"
echo -e "==========================================================${NC}"

# --- 1. VERIFICAÇÃO DE STATUS E VERSÃO ---
status "${WHITE}[1/4] Verificando integridade do sistema...${NC}"

NEEDS_ACTION=true

if [[ -f "$SCTL" ]]; then
    # Captura a versão instalada
    CURRENT_VERSION=$($SCTL version | awk '{print $NF}' || echo "0.0.0.0")
    # Verifica se o agente está operacional
    IS_OP=$($SCTL status | grep -i "Agent is operational" || true)

    if [[ "$CURRENT_VERSION" == "$TARGET_VERSION" ]] && [[ -n "$IS_OP" ]]; then
        status "${GREEN}Agente SentinelOne já está na versão $TARGET_VERSION e operacional. Saindo...${NC}"
        NEEDS_ACTION=false
        exit 0
    elif [[ "$CURRENT_VERSION" != "$TARGET_VERSION" ]]; then
        status "Versão detectada ($CURRENT_VERSION) difere da target ($TARGET_VERSION)."
    else
        status "${RED}Agente detectado mas não está operacional.${NC}"
    fi
else
    status "SentinelOne não encontrado no sistema."
fi

# --- 2. PREPARAÇÃO E DOWNLOAD ---
if [ "$NEEDS_ACTION" = true ]; then
    status "${WHITE}[2/4] Preparando ambiente de instalação...${NC}"
    
    DATE=$(date '+%Y-%m-%d-%H-%M-%S')
    TEMP_DIR="/tmp/S1-Download-$DATE"
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"

    # Cria o arquivo de token (essencial para o installer do macOS)
    echo "$SITE_TOKEN" > "$TEMP_DIR/com.sentinelone.registration-token"
    # Também copia para o /tmp padrão, pois alguns PKGs buscam lá
    cp "$TEMP_DIR/com.sentinelone.registration-token" "/tmp/com.sentinelone.registration-token"

    status "Baixando instalador..."
    if ! curl -L --fail --max-time 600 -o "$FILENAME" "$INSTALL_URL"; then
        status "${RED}❌ Falha crítica no download.${NC}"
        exit 1
    fi

    status "Verificando assinatura digital..."
    if ! spctl --assess --type install "$FILENAME"; then
        status "${RED}❌ Assinatura inválida. Abortando por segurança.${NC}"
        exit 1
    fi

    # --- 3. INSTALAÇÃO ---
    status "${WHITE}[3/4] Iniciando instalação/reparo...${NC}"
    if sudo /usr/sbin/installer -pkg "$FILENAME" -target /; then
        status "${GREEN}✅ Pacote processado pelo sistema.${NC}"
    else
        status "${RED}❌ Falha na execução do installer.${NC}"
        exit 1
    fi

    # Aguarda o daemon subir
    status "Aguardando inicialização dos serviços (20s)..."
    sleep 20
fi

# --- 4. VALIDAÇÃO FINAL ---
status "${WHITE}[4/4] Relatório Final${NC}"
if [[ -f "$SCTL" ]]; then
    FINAL_VERSION=$($SCTL version | awk '{print $NF}')
    FINAL_OP=$($SCTL status | grep -i "Agent is operational" || true)
    
    if [[ -n "$FINAL_OP" ]]; then
        echo -e "----------------------------------------------------------"
        echo -e " RESULTADO: ${GREEN}[SUCESSO] Agente $FINAL_VERSION Operacional.${NC}"
        echo -e "----------------------------------------------------------"
    else
        # Tenta um bind forçado se não estiver operacional
        status "Tentando vincular token manualmente..."
        sudo "$SCTL" management token set "$SITE_TOKEN" || true
        sudo "$SCTL" control start || true
        echo -e "${RED} RESULTADO: [ATENÇÃO] Instalado, mas aguardando ativação.${NC}"
    fi
else
    echo -e "${RED} RESULTADO: [ERRO] Falha ao localizar o binário após instalação.${NC}"
    exit 1
fi

# Remove token do /tmp global ao sair
rm -f "/tmp/com.sentinelone.registration-token"
