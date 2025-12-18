#!/bin/zsh

################################################################################
# SCRIPT: INSTALAÇÃO MOBILITY PRINT E LIMPEZA DE IMPRESSORAS (macOS)
################################################################################

# Variáveis
MOBILITY_PRINT_URL="https://cdn.papercut.com/web/products/mobility-print/installers/client/mac/mobility-print-client-installer.pkg"
PKG_PATH="/tmp/mobility-print-client.pkg"
CLOUD_CONFIG_URL="https://mp.cloud.papercut.com/?token=eyJhbGciOiJSUzI1NiIsIm9yZyI6Im9yZy1DMUNCVE04NiIsInNydiI6InNydi1OWU1aUVk2RiIsInR5cCI6IkpXVCJ9.eyJpYXQiOjE3NjQwMzg3NDcsImlzcyI6InNydi1OWU1aUVk2RiIsImp0aSI6IjhUTjdDSzhZIiwibG5rIjoiOFRON0NLOFkiLCJvcmciOiJvcmctQzFDQlRNODYiLCJzcnYiOiJzcnYtTllNWlFZNkYiLCJzdWIiOiJ0b2tlbkNyZWF0aW9uIn0.itDFtOvuy1b2xpaRosrzNPrPs7EY-YOdCpdzX-VqXNhoxUaC486WU7g0x5aZCU6WCqIBP_hnUDi7yVvelmMLBD78sawBoj_1mH_rVdtWEKi_njTZOei85X7tmK4ZUYhgbExBamQ1MAIrjGRQczExBqtIk8vY09Vh5SxZ9CjDV-jlPdFBAPPdCq6xkPIzb_rjWmskwoGk7aIP4c33qitO-FAInam42-sKGH-ShIsUfbdaz9Q3nO2kVU0A-ruevoAx_Zrs-Tz3pKPHte09cHxJV8VN-iZwIO313G4JxpgSctNAapOAOqBpZBKsh40pUz0aygp-sh5_1aYgOrrwsJxQkytxTI3gMJZliunZsudmv3WT1ae4dlwpiZrUTPDF-6Z5lGG8dsNeRrVTWWHK0OGqFI4Z5c1OWaEE6f9-UWqeNRSgD82jVwh5QoQv4AY2S1uKybrdYP0MkoI8yvixUWk_Dp2oE4z8GOGB3DR6kDda6HmLFJWjTgNQrRtuiXP-sg5aJvN6cSRZadEQpjH28aFY95yBtY7C7SwwcNcwxg5HfbkxUgazPiEmoGR9W6MWUsu6k9crd6iG0wKRWxIxMHDk-UDWBNkbVjDi5ryku_pM-Sn6gwmLPXl-GAI6arKv6510Q1UVK7KdoXC58ubIManafU5LL-YIVj1dgUO436cLsdM"

# Lista de impressoras para remover
TARGET_PRINTERS=(
    "PRINT-ARCO-FOR-BLACK"
    "PRINT-ARCO-FOR-COLOR"
    "PRINT-ARCO-SC-BLACK"
    "PRINT-HUB-BLACK"
    "PRINT-HUB-BLACK-3ANDAR"
    "PRINT-HUB-BLACK-TERREO"
    "PRINT-HUB-COLOR"
    "PRINT-HUB-COLOR-2ANDAR"
    "PRINT-ARCO-SP-10º_ANDAR"
    "PRINT-ARCO-DIR-SP"
    "PRINT-ARCO-SP-BLACK"
    "PRINT-ARCO-SP-COLOR"
)

# ---------------------------------------------------------
# FUNÇÃO: Instalação do Mobility Print
# ---------------------------------------------------------
install_mobility_print() {
    echo "STATUS: Verificando Mobility Print..."
    if [ -d "/Applications/PaperCut Mobility Print Client" ]; then
        echo "SUCESSO: Mobility Print já instalado."
        return 0
    fi

    echo "STATUS: Baixando instalador..."
    curl -L "$MOBILITY_PRINT_URL" -o "$PKG_PATH"

    echo "STATUS: Instalando PKG..."
    sudo installer -pkg "$PKG_PATH" -target /
    
    rm -f "$PKG_PATH"
}

# ---------------------------------------------------------
# FUNÇÃO: Configuração via Token Cloud
# ---------------------------------------------------------
configure_client() {
    echo "STATUS: Aplicando configuração de nuvem..."
    # O binário no macOS fica dentro do .app
    local APP_BIN="/Applications/PaperCut Mobility Print Client/PaperCut Mobility Print Client.app/Contents/MacOS/mobility-print-client"
    
    if [ -f "$APP_BIN" ]; then
        # Executa em background para não travar o script
        "$APP_BIN" -url "$CLOUD_CONFIG_URL" &
        sleep 5
        return 0
    else
        echo "ERRO: Binário de configuração não encontrado."
        return 1
    fi
}

# ---------------------------------------------------------
# FUNÇÃO: Remover Impressoras Antigas
# ---------------------------------------------------------
remove_old_printers() {
    echo "STATUS: Removendo impressoras legadas..."
    # Obtém a lista de impressoras instaladas via lpstat
    INSTALLED_PRINTERS=$(lpstat -a | awk '{print $1}')

    for PRINTER in "${TARGET_PRINTERS[@]}"; do
        if echo "$INSTALLED_PRINTERS" | grep -q "$PRINTER"; then
            echo "REMOVENDO: $PRINTER"
            sudo lpadmin -x "$PRINTER"
        fi
    done
}

# ---------------------------------------------------------
# EXECUÇÃO PRINCIPAL
# ---------------------------------------------------------

install_mobility_print

if [ $? -eq 0 ]; then
    configure_client
    
    echo "STATUS: Aguardando 30s para propagação das impressoras..."
    sleep 30
    
    # Validação (verifica se a FINDME apareceu)
    if lpstat -a | grep -i "PRINT-ARCO-FINDME" > /dev/null; then
        echo "SUCESSO: Impressora FINDME detectada!"
        remove_old_printers
        echo "PROCESSO FINALIZADO COM SUCESSO."
    else
        echo "AVISO: FINDME não detectada. Limpeza abortada por segurança."
    fi
fi
