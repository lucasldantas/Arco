#!/bin/bash

# --- CONFIGURAÇÕES ATUALIZADAS ---
SITE_TOKEN="eyJ1cmwiOiAiaHR0cHM6Ly91c2VhMS0wMTYuc2VudGluZWxvbmUubmV0IiwgInNpdGVfa2V5IjogIjM2ZWM1YmJmNDVhOTRiZjAifQ=="
INSTALL_URL="https://temp-arco-itops.s3.us-east-1.amazonaws.com/MACOS_Sentinel-Release-25-3-1-8253_macos_v25_3_1_8253.pkg"
TARGET_VERSION="25.3.1.8253"
PKG_PATH="/tmp/sentineloneagent.pkg"
TOKEN_FILE="/tmp/com.sentinelone.registration-token"
SCTL="/usr/local/bin/sentinelctl"

# Cores para o output
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

clear
echo -e "${CYAN}=========================================================="
echo -e "            SENTINELONE - HOT FIX $TARGET_VERSION"
echo -e "==========================================================${NC}"

# --- 1. VERIFICAÇÃO INICIAL ---
echo -e "\n${WHITE}[1/4] Verificando integridade do sistema...${NC}"

NEEDS_UPDATE=false
NEEDS_FIX=false

if [ ! -f "$SCTL" ]; then
    echo -e " >> STATUS: Sentinel não encontrado no diretório padrão."
    NEEDS_UPDATE=true
else
    # Captura status e versão
    STATUS_OUTPUT=$($SCTL status 2>&1)
    CURRENT_VERSION=$(echo "$STATUS_OUTPUT" | grep "Agent version:" | awk '{print $NF}')
    
    # Verifica se os daemons estão rodando
    IS_OPERATIONAL=$(echo "$STATUS_OUTPUT" | grep -i "Agent is operational")
    
    if [[ -z "$CURRENT_VERSION" ]]; then CURRENT_VERSION="0.0.0"; fi

    # Comparação de versão
    if [[ "$CURRENT_VERSION" < "$TARGET_VERSION" ]]; then
        echo -e " >> STATUS: Versão desatualizada ($CURRENT_VERSION).${CYAN}"
        NEEDS_UPDATE=true
    elif [[ -z "$IS_OPERATIONAL" ]]; then
        echo -e " >> STATUS: Componentes corrompidos ou descarregados.${RED}"
        NEEDS_FIX=true
    else
        echo -e " >> STATUS: Sentinel funcional e atualizado ($CURRENT_VERSION).${GREEN}"
    fi
fi

# --- 2. EXECUÇÃO DA ATUALIZAÇÃO ---
if [ "$NEEDS_UPDATE" = true ]; then
    echo -e "\n${WHITE}[2/4] Iniciando Atualização/Instalação...${NC}"
    echo -e "${GRAY} -> Gerando arquivo de token...${NC}"
    echo "$SITE_TOKEN" > "$TOKEN_FILE"
    
    echo -e "${GRAY} -> Baixando instalador oficial...${NC}"
    curl -L -o "$PKG_PATH" "$INSTALL_URL" --silent --show-error --fail
    
    if [ $? -eq 0 ]; then
        echo -e "${GRAY} -> Executando instalação silenciosa (v$TARGET_VERSION)...${NC}"
        # No macOS, o token deve estar no /tmp antes do installer rodar
        sudo installer -pkg "$PKG_PATH" -target /
        
        echo -e "${GRAY} -> Aguardando inicialização dos serviços...${NC}"
        sleep 20
        NEEDS_FIX=true
    else
        echo -e " ${RED}[!] ERRO CRÍTICO: Falha ao baixar o arquivo .pkg.${NC}"
    fi
else
    echo -e "\n${WHITE}[2/4] Atualização não necessária.${GRAY}"
fi

# --- 3. APLICAÇÃO DOS FIXES ---
if [ "$NEEDS_FIX" = true ]; then
    echo -e "\n${WHITE}[3/4] Aplicando comandos de reparo...${NC}"
    if [ -f "$SCTL" ]; then
        echo -e "${GRAY} -> Vinculando Token e forçando conexão...${NC}"
        sudo "$SCTL" management token set "$SITE_TOKEN"
        sudo "$SCTL" control start
        sleep 5
    fi
else
    echo -e "\n${WHITE}[3/4] Nenhuma correção de serviços necessária.${NC}"
    echo -e "${GREEN} -> SentinelOne íntegro.${NC}"
fi

# --- 4. VALIDAÇÃO FINAL ---
echo -e "\n${WHITE}[4/4] Relatório Final de Operação${NC}"
echo -e "${CYAN}----------------------------------------------------------${NC}"

if [ -f "$SCTL" ]; then
    FINAL_STATUS=$($SCTL status 2>&1)
    IS_FUNCTIONAL=$(echo "$FINAL_STATUS" | grep -i "Agent is operational")
    IS_ONLINE=$(echo "$FINAL_STATUS" | grep -i "Established")

    if [[ -n "$IS_FUNCTIONAL" && -n "$IS_ONLINE" ]]; then
        echo -e " RESULTADO: ${GREEN}[SUCESSO] Agente Online e Protegido.${NC}"
    else
        echo -e " RESULTADO: ${RED}[FALHA] Componentes ainda offline. Verifique o status manual.${NC}"
    fi
else
    echo -e " RESULTADO: ${RED}[ERRO] Binários não encontrados após execução.${NC}"
fi
echo -e "${CYAN}----------------------------------------------------------${NC}"

# Limpeza
rm -f "$PKG_PATH"
rm -f "$TOKEN_FILE"
