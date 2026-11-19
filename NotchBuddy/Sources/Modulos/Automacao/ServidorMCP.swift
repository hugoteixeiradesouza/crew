import Foundation

// Servidor MCP do Crew (stdio, JSON-RPC 2.0, uma mensagem por linha). Script Python pequeno,
// instalado ao lado do nb-hook; repassa cada chamada ao Crew pelo mesmo socket (nb.sock) e
// devolve a resposta. Crew fechado = a ferramenta responde que o Crew não está aberto.

enum ServidorMCP {
    static var caminho: String { HookServer.supportDir.appendingPathComponent("crew-mcp.py").path }

    /// Grava (ou atualiza) o script. Barato: só escreve se mudou.
    static func instalarScript() {
        let atual = try? String(contentsOfFile: caminho, encoding: .utf8)
        guard atual != script else { return }
        try? FileManager.default.createDirectory(at: HookServer.supportDir, withIntermediateDirectories: true)
        try? script.write(toFile: caminho, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: caminho)
    }

    static let script = #"""
#!/usr/bin/env python3
# Servidor MCP do Crew — gerado pelo app Crew. Não edite: o Crew regrava.
import sys, json, socket, os

SOCK = os.path.expanduser('~/Library/Application Support/NotchBuddy/nb.sock')

TOOLS = [
    {'name': 'estado_do_mac',
     'description': 'Estado do Mac agora: uso de CPU (total e núcleos de eficiência/desempenho), memória (em uso, pressão, swap), temperatura da CPU, disco (livre/total), bateria (nível, carregando, saúde) e carga.',
     'inputSchema': {'type': 'object', 'properties': {}}},
    {'name': 'sessoes_abertas',
     'description': 'Sessões do Claude Code que o Crew está acompanhando: projeto, título, estado (trabalhando, esperando aprovação, parada…) e pasta.',
     'inputSchema': {'type': 'object', 'properties': {}}},
    {'name': 'avisar_no_notch',
     'description': 'Mostra um aviso curto no notch deste Mac (até 120 caracteres), com o Homie reagindo. Use para avisar o usuário de que algo terminou ou precisa dele.',
     'inputSchema': {'type': 'object', 'properties': {'texto': {'type': 'string'}}, 'required': ['texto']}},
    {'name': 'abrir_no_crew',
     'description': 'Abre a ilha do Crew (numa aba de módulo) ou a janela Central (numa página de módulo). Módulos: sistema, disco, agentes, audio, modelos, uso, sessoes…',
     'inputSchema': {'type': 'object', 'properties': {'onde': {'type': 'string', 'enum': ['ilha', 'central']}, 'modulo': {'type': 'string'}}, 'required': ['onde']}},
    {'name': 'videos',
     'description': 'Vídeos do Crew (Remotion): se o motor está instalado, os projetos de vídeo (pasta e composições já lidas), os vídeos prontos, a renderização em curso (fase e quadros) e o último erro. Use para acompanhar uma renderização.',
     'inputSchema': {'type': 'object', 'properties': {}}},
    {'name': 'video_criar',
     'description': 'Cria um projeto de vídeo do Remotion no motor do Crew, com um vídeo de partida (composição "Abertura", 1920x1080, 30 fps). Devolve a pasta: edite Raiz.tsx lá. Leia antes o CLAUDE.md da pasta do motor (dois níveis acima do projeto).',
     'inputSchema': {'type': 'object', 'properties': {'nome': {'type': 'string', 'description': 'Nome do projeto (vira o nome da pasta)'}, 'titulo': {'type': 'string', 'description': 'Texto do vídeo de partida'}}, 'required': ['nome']}},
    {'name': 'video_renderizar',
     'description': 'Renderiza uma composição de um projeto de vídeo do Crew em MP4 (Filmes/Crew). Começa e volta na hora: acompanhe com a ferramenta `videos`. O andamento aparece no notch. Uma renderização por vez.',
     'inputSchema': {'type': 'object', 'properties': {'projeto': {'type': 'string'}, 'composicao': {'type': 'string', 'description': 'id da <Composition>'}, 'props': {'type': 'object', 'description': 'Opcional: troca os defaultProps da composição'}}, 'required': ['projeto', 'composicao']}},
    {'name': 'falar',
     'description': 'Fala um texto em voz alta neste Mac, com a voz do computador escolhida no Crew (voz humanizada local ou voz do macOS). Use só quando o usuário pedir para ouvir algo ou para ser avisado por voz. Texto curto (até 600 caracteres), em português, sem markdown. Volta na hora: a voz humanizada leva alguns segundos para começar.',
     'inputSchema': {'type': 'object', 'properties': {'texto': {'type': 'string'}, 'voz': {'type': 'string', 'description': 'Opcional: nome de uma voz humanizada do Crew (veja `vozes`). Sem isso, fala a voz padrão.'}}, 'required': ['texto']}},
    {'name': 'vozes',
     'description': 'A voz do computador no Crew: qual motor de fala está em uso (macOS ou voz humanizada), se o motor de voz humanizada está instalado e ligado, as vozes humanizadas criadas (nome, origem, qual é a padrão) e as vozes do macOS em português.',
     'inputSchema': {'type': 'object', 'properties': {}}},
]

def crew(pedido, timeout=20):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(timeout)
    s.connect(SOCK)
    s.sendall((json.dumps({'crew_mcp': pedido}) + '\n').encode())
    dados = b''
    while not dados.endswith(b'\n'):
        c = s.recv(65536)
        if not c:
            break
        dados += c
    s.close()
    return json.loads(dados or b'{}')

def enviar(o):
    sys.stdout.write(json.dumps(o, ensure_ascii=False) + '\n')
    sys.stdout.flush()

for linha in sys.stdin:
    linha = linha.strip()
    if not linha:
        continue
    try:
        msg = json.loads(linha)
    except Exception:
        continue
    mid, metodo = msg.get('id'), msg.get('method')
    if metodo == 'initialize':
        versao = (msg.get('params') or {}).get('protocolVersion', '2025-06-18')
        enviar({'jsonrpc': '2.0', 'id': mid, 'result': {'protocolVersion': versao, 'capabilities': {'tools': {}},
                'serverInfo': {'name': 'crew', 'version': '1'}}})
    elif metodo == 'tools/list':
        enviar({'jsonrpc': '2.0', 'id': mid, 'result': {'tools': TOOLS}})
    elif metodo == 'tools/call':
        p = msg.get('params') or {}
        try:
            r = crew({'ferramenta': p.get('name'), 'args': p.get('arguments') or {}})
            erro = 'erro' in r
            texto = r.get('erro') if erro else json.dumps(r, ensure_ascii=False, indent=1)
        except Exception:
            erro, texto = True, 'O Crew não está aberto neste Mac.'
        enviar({'jsonrpc': '2.0', 'id': mid, 'result': {'content': [{'type': 'text', 'text': texto}], 'isError': erro}})
    elif metodo == 'ping':
        enviar({'jsonrpc': '2.0', 'id': mid, 'result': {}})
    elif mid is not None:
        enviar({'jsonrpc': '2.0', 'id': mid, 'error': {'code': -32601, 'message': 'método desconhecido'}})
"""#
}
