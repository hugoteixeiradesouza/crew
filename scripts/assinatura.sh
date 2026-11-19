#!/bin/bash
# Descobre como assinar o build NESTE Mac. É lido com `source` pelo instalar.sh e pelo integrar.sh;
# sozinho, mostra o que seria usado:  scripts/assinatura.sh
#
# Define:
#   ASSINATURA       argumentos de assinatura para o xcodebuild
#   ASSINATURA_TIPO  "certificado" (Apple Development do dono do Mac) ou "local" (sem certificado)
#   ASSINATURA_TIME  o time do certificado, quando há
#
# Com certificado, o macOS reconhece o app de um build para o outro e as permissões
# (Acessibilidade, microfone, gravação de tela) ficam. Com assinatura local o app roda igual,
# mas cada build novo é um app novo para o macOS: ele pede as permissões de novo.
#
#   CREW_TEAM=XXXXXXXXXX   escolhe o time (para quem tem mais de um certificado)
#   CREW_ASSINATURA=local  força a assinatura local

ASSINATURA_TIME="${CREW_TEAM:-}"
if [ "${CREW_ASSINATURA:-}" = "local" ]; then
    ASSINATURA_TIME=""
elif [ -z "$ASSINATURA_TIME" ]; then
    # Primeiro certificado "Apple Development" válido das chaves; o time é o OU dele.
    _cert="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)"
    if [ -n "$_cert" ]; then
        ASSINATURA_TIME="$(security find-certificate -c "$_cert" -p 2>/dev/null \
            | openssl x509 -noout -subject -nameopt multiline 2>/dev/null \
            | sed -n 's/^ *organizationalUnitName *= *//p' | head -1)"
    fi
    unset _cert
fi

if [ -n "$ASSINATURA_TIME" ]; then
    ASSINATURA_TIPO="certificado"
    ASSINATURA=(DEVELOPMENT_TEAM="$ASSINATURA_TIME" CODE_SIGN_IDENTITY="Apple Development" OTHER_CODE_SIGN_FLAGS="")
else
    ASSINATURA_TIPO="local"
    ASSINATURA=(DEVELOPMENT_TEAM="" CODE_SIGN_IDENTITY="-" OTHER_CODE_SIGN_FLAGS="")
fi

# Chamado direto (não por `source`): diz o que achou.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    if [ "$ASSINATURA_TIPO" = "certificado" ]; then
        echo "Assinatura: certificado Apple Development, time $ASSINATURA_TIME"
    else
        echo "Assinatura: local (nenhum certificado Apple Development neste Mac)"
    fi
fi
