UI = {
    "guide_title": "PhotoVideoBackup — Guia do utilizador",
    "tagline": "Copie as suas fotos e vídeos para um SSD externo, um cartão SD ou um NAS — a partir do seu iPhone ou do seu telemóvel Android.",
    "version_line": "Guia do PhotoVideoBackup 2.6 (iPhone, iOS 16 ou posterior) e 1.0 (Android 9 ou posterior)",
    "toc": "Índice",
    "privacy_link": "Política de privacidade",
    "contact": "Suporte",
    "back": "Voltar ao guia do utilizador",
    "footer": "PhotoVideoBackup · Fotos e vídeos, copiados em segurança",
    "chooser_tagline": "Copie as suas fotos e vídeos em segurança",
    "chooser_privacy": "Política de privacidade",
}

GUIDE = [
    ("what", "O que é o PhotoVideoBackup?", [
        ("p", "O PhotoVideoBackup copia as suas fotos e vídeos do telemóvel — ou de um cartão de memória de câmara — para um SSD portátil, uma unidade USB ou um <b>NAS</b>. Os seus ficheiros nunca passam por um serviço online: a aplicação não tem servidor nem conta."),
        ("ul", ["O armazenamento do telemóvel está cheio e quer libertar espaço em segurança.", "Voltou de viagem com um cartão SD cheio de imagens (DJI, GoPro, Insta360, Blackmagic…) e quer protegê-las de imediato.", "Quer uma cópia pessoal que não dependa do iCloud nem do Google Fotos."]),
        ("p", "<b>O que a torna fiável?</b> Cada ficheiro copiado é lido de novo e verificado com uma impressão digital matemática (SHA-256). Se um único byte estiver errado, a aplicação avisa — nunca terá uma cópia danificada sem o saber."),
        ("p", "A aplicação apenas <b>copia</b>. Nunca move nem apaga nada da origem, a não ser que o peça expressamente depois de uma cópia (ver «Histórico e relatórios»)."),
    ]),
    ("pro", "Grátis e Pro", [
        ("p", "O PhotoVideoBackup é gratuito. Uma compra <b>Pro</b> — paga uma só vez, <b>sem subscrição</b> — desbloqueia as funções avançadas:"),
        ("table", ["Função", "Grátis", "Pro"], [
            ["Copiar a biblioteca de fotos para uma unidade ou pasta", "✓", "✓"],
            ["Explorar e pré-visualizar as cópias (pré-visualização de LUT incluída)", "✓", "✓"],
            ["Copiar cartões de câmaras e unidades USB (SD, DJI, GoPro, Insta360…)", "—", "✓"],
            ["Espelho numa segunda unidade", "—", "✓"],
            ["Copiar para um NAS por Wi-Fi", "—", "✓"],
            ["Aplicar uma LUT a vídeos LOG (exportação H.265)", "—", "✓"],
        ]),
        ("fig", "paywall", "O ecrã de atualização. Abra-o quando quiser a partir do separador Definições."),
    ]),
    ("need", "O que precisa", [
        ("table", ["", "iPhone / iPad", "Android"], [
            ["O dispositivo", "Um iPhone com porta USB-C (iPhone 15 ou posterior), iOS 16 ou posterior", "Um telemóvel ou tablet Android, Android 9 ou posterior"],
            ["Uma unidade", "Qualquer SSD USB-C (Samsung T7, SanDisk Extreme, WD My Passport…)", "Qualquer SSD ou pen USB-C, ou uma pasta do telemóvel"],
            ["Um hub ou leitor (opcional)", "Um pequeno hub USB-C para ligar em conjunto um SSD e um leitor de cartões", "Um leitor de cartões USB-C ou um hub OTG"],
        ]),
        ("note", "Copiar muito vídeo gasta bateria. Ligue o telemóvel ao carregador ou comece com boa carga."),
    ]),
    ("start", "Primeiro arranque e permissões", [
        ("p", "Um ecrã de boas-vindas apresenta a aplicação e cinco montagens típicas — do simples telemóvel → SSD até um NAS acedido por VPN. Toque em <b>Começar</b>."),
        ("fig", "onboarding_simple", "A montagem mais simples: telemóvel → SSD."),
        ("ul", ["<b>iPhone / iPad</b>: permita o <b>acesso total</b> à biblioteca de fotos. Sem ele, a aplicação não consegue ler as suas fotos.", "<b>Android</b>: permita o acesso às suas fotos e vídeos. Permita também o acesso à <b>localização das fotos</b> — caso contrário o Android retira os dados GPS dos ficheiros que fornece e a cópia não seria o original. Permita as notificações para ser avisado no fim de uma cópia."]),
        ("note", "A aplicação só lê as suas fotos para as copiar. Não as modifica, não as partilha nem as envia para lado nenhum."),
    ]),
    ("setup", "Defina o nome do dispositivo e o destino", [
        ("ol", ["Abra o separador <b>Definições</b>. Na secção <b>Dispositivo</b>, escreva um <b>nome da pasta</b> — por exemplo <i>iPhone da Ana</i> ou <i>Pixel 8</i>. Passa a ser o nome da pasta na unidade, de modo que dois telemóveis que copiam para a mesma unidade ficam separados. Uma cópia não arranca enquanto não houver um nome.", "Ligue a sua unidade.", "Em <b>Destinos</b>, toque em <b>Escolher…</b> e selecione a unidade, ou uma pasta dela, no explorador de ficheiros do sistema. No Android pode também escolher uma pasta do armazenamento do telemóvel.", "O nome da unidade aparece nas Definições e no separador Backup, com o espaço livre. Só o faz uma vez: da próxima vez a aplicação reconhece a unidade."]),
        ("fig", "settings_configured", "Definições: nome do dispositivo e primeiro destino."),
        ("note", "Um destino também pode ser uma pasta do <b>iCloud Drive</b> (iPhone) — a aplicação liberta a cópia local quando o iCloud confirma o envio, para que o telemóvel não encha."),
    ]),
    ("photos", "Copie as suas fotos e vídeos", [
        ("p", "Abra o separador <b>Backup</b>. Em cima vê os seus destinos com o espaço livre. Em <b>Fontes</b>, a linha <b>Biblioteca de Fotos</b> mostra o nome do seu dispositivo. Toque no botão <b>Backup</b> dessa linha."),
        ("fig", "dashboard_ready", "O separador Backup: destino ligado, biblioteca de fotos pronta."),
        ("p", "A aplicação analisa a biblioteca e depois copia. A <b>primeira cópia é a mais demorada</b>; as seguintes só copiam o que é novo e são muito mais rápidas."),
        ("ul", ["As fotos guardadas apenas no iCloud / Google Fotos são primeiro transferidas — é preciso ligação e algum tempo.", "A aplicação copia cada ficheiro diretamente para o destino, por isso funciona mesmo com o telemóvel quase cheio.", "Pode sair da aplicação: uma notificação avisa quando a cópia termina."]),
    ]),
    ("sd", "Copie um cartão de câmara (Pro)", [
        ("ol", ["Ligue o leitor de cartões ao telemóvel e introduza o cartão (use um hub se o SSD também tiver de ficar ligado).", "No separador Backup, toque em <b>Adicionar fonte (SD, USB…)</b>, localize o cartão no explorador de ficheiros e confirme.", "Dê um nome à fonte — <i>Blackmagic</i>, <i>Viagem ao Japão</i>… O tipo de dispositivo é reconhecido automaticamente.", "Toque em <b>Backup</b> na linha da fonte."]),
        ("table", ["Dispositivo reconhecido", "O que é copiado"], [
            ["DJI Mini 3 Pro", "Fotos, vídeos, DNG e a telemetria (.srt)"],
            ["DJI 360 / Action (Neo 2…)", "Vídeos, fotos, DNG, áudio e a telemetria (.srt)"],
            ["Insta360 (X5…)", "Ficheiros .insv, .insp e .lrv"],
            ["GoPro HERO", "Vídeos e fotos; os ficheiros proxy (.lrv) e de miniaturas (.thm) são ignorados"],
            ["Qualquer outro", "Formatos comuns de foto, vídeo e RAW"],
        ]),
        ("note", "Um cartão ejetado e reintroduzido precisa de um toque em <b>Reconectar</b>: o sistema dá à aplicação um novo acesso de cada vez que o cartão é montado. O nome e o tipo da fonte mantêm-se."),
        ("p", "Para retirar uma fonte da lista, use o <b>–</b> vermelho (iPhone) ou o botão de remover da linha (Android). Nenhum ficheiro é apagado."),
    ]),
    ("progress", "Enquanto a cópia decorre", [
        ("p", "Surge um painel <b>Backup em curso</b> assim que toca em Backup. Primeiro <b>Preparando…</b> (ligação aos destinos) e depois <b>A analisar a origem…</b> com um contador em direto dos ficheiros encontrados — numa biblioteca grande pode demorar um pouco, não está bloqueado."),
        ("fig", "progress_backup", "Backup em curso: percentagem, ficheiros feitos, tempo restante, ficheiro atual."),
        ("table", ["Fase", "O que a aplicação faz"], [
            ["Análise", "Conta os ficheiros e verifica quais é preciso copiar."],
            ["Cópia", "Escreve o ficheiro no destino."],
            ["Verificação", "Lê a cópia de novo e compara-a com o original."],
            ["Ignorados", "O ficheiro já está copiado — nada a fazer."],
        ]),
        ("note", "Não desligue a unidade nem o cartão enquanto a cópia decorre. Se uma unidade desaparecer mesmo assim, os outros destinos continuam e a sessão fica marcada como <b>Parcial</b>."),
        ("p", "Um botão <b>Parar</b> termina a cópia de forma limpa a qualquer momento. Definições → Backup tem também um limite <b>Máx. ficheiros por sessão</b>: deixe vazio para ilimitado."),
    ]),
    ("done", "Quando a cópia termina", [
        ("fig", "completion_banner", "O aviso final: copiados, ignorados, falhados, tamanho e duração."),
        ("table", ["Número", "Significado"], [
            ["Copiados", "Ficheiros guardados pela primeira vez no destino."],
            ["Ignorados", "Ficheiros que já lá estavam — normal e sem risco."],
            ["Falhados", "Ficheiros que não foi possível copiar (raro)."],
        ]),
        ("p", "Uma falha vem de um cartão danificado, uma unidade cheia, uma ligação interrompida ou de um único ficheiro demasiado grande para o espaço livre — só esse ficheiro é assinalado e o resto continua. Liberte espaço ou volte a ligar e execute a cópia de novo: os ficheiros em falta são recuperados."),
    ]),
    ("history", "Histórico e relatórios", [
        ("p", "O separador <b>Histórico</b> lista cada cópia: origem, destinos, estrutura de pastas, número de ficheiros e uma cor — verde para sucesso, laranja para <b>Parcial</b>, vermelho se houve falhas."),
        ("fig", "history_list", "Histórico: uma sessão concluída."),
        ("p", "<b>Parcial</b> significa que a cópia parou antes do fim, por uma de três razões que o relatório indica: tocou em <b>Parar</b>, o <b>limite de ficheiros</b> foi atingido ou um <b>destino foi desligado</b>. Volte a ligar a unidade e execute de novo — continua onde parou."),
        ("p", "Toque numa sessão para ver o relatório: resumo, estado SHA-256 e listas de ficheiros copiados, ignorados e falhados — com o motivo de cada falha. Com dois destinos, o relatório mostra cada unidade em separado."),
        ("fig", "report_summary", "Um relatório de sessão."),
        ("p", "<b>Eliminar ficheiros fonte…</b> liberta espaço no cartão ou na biblioteca quando estiver satisfeito com a cópia. Só oferece os ficheiros copiados <i>e</i> verificados, e para confirmar tem de escrever um código de quatro dígitos. A sua cópia não é tocada. No iPhone e no Android, o sistema pede mais uma confirmação para as fotos."),
        ("fig", "report_delete_confirm", "Escrever o código confirma a eliminação."),
        ("note", "<b>Limpar histórico</b> só remove os registos dentro da aplicação. Os seus ficheiros ficam onde estão."),
    ]),
    ("browse", "Explore, veja e partilhe as suas cópias", [
        ("p", "O separador <b>Explorar</b> mostra, dentro da aplicação, o que há nas suas unidades: uma pasta por dispositivo, depois as pastas por data e depois uma grelha de miniaturas. Toque numa foto para a abrir em ecrã inteiro — deslize para mudar de ficheiro, junte os dedos para ampliar — ou toque num vídeo para o reproduzir. A unidade tem de estar ligada."),
        ("fig", "browse_device_folders", "Explorar: as pastas de dispositivo de uma unidade."),
        ("fig", "browse_media_grid", "A grelha de conteúdos de um dia."),
        ("p", "Para enviar ficheiros para outro lado: toque em <b>Selecionar</b>, assinale os ficheiros e depois em <b>Partilhar</b> — AirDrop, mensagens, e-mail, outra aplicação."),
        ("fig", "android_viewer", "Android: o visualizador em ecrã inteiro."),
        ("p", "Num NAS, Explorar lista os ficheiros e só transfere cada um quando o abre."),
    ]),
    ("naming", "Pastas e nomes de ficheiros", [
        ("p", "Em <b>Definições → Backup</b>, <b>Estrutura de pastas</b> define como se organiza uma pasta de dispositivo: <i>Flat</i> (plana), <i>By month</i> (por mês), <i>By date</i> (por data, predefinição) ou <i>By year / month</i> (ano / mês). O separador Explorar adapta-se ao que existe na unidade."),
        ("p", "<b>Nomes dos ficheiros</b> dá a cada ficheiro o seu nome definitivo <b>no momento da primeira cópia</b> — nunca é guardado com o nome da câmara e renomeado depois. Ative <b>Mudar o nome dos ficheiros durante a cópia</b> e edite o padrão: toque num símbolo para o inserir, tudo o resto é texto literal. Uma linha <b>Exemplo</b> mostra o resultado."),
        ("fig", "settings_file_naming", "Nomes dos ficheiros: padrão, símbolos e exemplo em direto."),
        ("table", ["Símbolo", "Substituído por"], [
            ["{YYYY} {MM} {DD}", "Ano, mês e dia da captura"],
            ["{hh} {mm} {ss}", "Hora, minuto e segundo da captura (hora local)"],
            ["{device}", "O nome da pasta do dispositivo, sem espaços"],
            ["{original}", "O nome original do ficheiro, sem a extensão"],
        ]),
        ("ul", ["<b>Nunca se substitui nada.</b> Se o nome estiver ocupado por um ficheiro diferente, o novo recebe um sufixo <code>-1</code>, <code>-2</code>… Inclua os segundos no padrão para que duas fotografias simultâneas mantenham nomes diferentes.", "<b>Os duplicados são reconhecidos por esse nome.</b> Um ficheiro já copiado é ignorado — mesmo que o tenha editado entretanto — e um ficheiro diferente com o mesmo nome fica à parte.", "<b>Os ficheiros existentes não são renomeados.</b> O perfil aplica-se aos ficheiros copiados a partir de agora. Com o perfil desativado (predefinição) os ficheiros mantêm o nome da câmara."]),
        ("p", "Pode também adicionar <b>extensões de ficheiro adicionais</b> para copiar junto com os conteúdos — por exemplo os registos GPS <code>gpx</code>."),
    ]),
    ("lut", "LUT Grade: dar o aspeto às imagens LOG (Pro)", [
        ("p", "As imagens filmadas em <b>LOG</b> (DJI D-Log M, GoPro Protune…) parecem planas e cinzentas até se aplicar uma <b>LUT</b>. Em Explorar, atribua uma LUT a uma pasta de dispositivo para pré-visualizar e fazer a gradação sem sair da aplicação."),
        ("ol", ["Abra uma pasta de dispositivo e, em <b>LUT Grade</b>, toque em <b>Atribuir LUT…</b> e depois em <b>Importar LUT (.cube)…</b>. Serve qualquer ficheiro <code>.cube</code> padrão (DaVinci Resolve, Final Cut Pro, o fabricante da sua câmara).", "Toque num vídeo dessa pasta: é reproduzido com a LUT aplicada em tempo real. Esta pré-visualização é <b>gratuita</b>.", "Para criar cópias permanentes (Pro), toque em <b>Selecionar</b>, escolha os vídeos e depois em <b>Gradação</b>. Cada um é recodificado em <b>H.265</b> com a LUT incorporada, numa pasta irmã chamada <b>Dispositivo (Graded)</b>."]),
        ("fig", "browse_lut_picker", "Escolher uma LUT para uma pasta."),
        ("fig", "android_lut", "Android: a secção LUT Grade de uma pasta de dispositivo."),
        ("ul", ["A gradação faz-se vídeo a vídeo, nunca «tudo» — uma pasta mistura muitas vezes clipes LOG e normais, e uma LUT LOG estragaria os normais.", "Os ficheiros já graduados são ignorados, por isso pode repetir sem risco. Cancele quando quiser: os terminados ficam.", "A gradação é exigente: mantenha a aplicação aberta e a unidade ligada. O telemóvel pode aquecer.", "Num NAS, os clipes são transferidos, graduados no telemóvel e enviados para uma pasta <b>Dispositivo (Graded)</b> do NAS — mais lento e gasta dados."]),
    ]),
    ("mirror", "Dois destinos ao mesmo tempo (Pro)", [
        ("p", "Nas Definições, adicione um segundo destino: cada ficheiro é copiado para ambos em simultâneo — duas unidades, ou uma unidade e um NAS. A cópia não demora o dobro. Se um destino falhar ou desaparecer, <b>o outro continua</b>, e o relatório diz o que falta a qual."),
        ("note", "Se no arranque só uma das duas unidades estiver ligada, a aplicação copia na mesma para ela e marca a sessão como incompleta para a outra."),
    ]),
    ("nas", "Copie para um NAS por Wi-Fi (Pro)", [
        ("p", "Em vez de uma unidade — ou além dela — pode copiar diretamente para um <b>NAS</b> (Synology, QNAP, TrueNAS, qualquer equipamento que fale SMB) através da rede. Sem cabo, sem nuvem, e cada ficheiro é verificado com SHA-256."),
        ("ol", ["No NAS, ative a <b>partilha de ficheiros SMB</b> e dê a um utilizador acesso de leitura e escrita a uma pasta partilhada.", "Na aplicação: <b>Definições → Destinos → NAS (SMB)</b>.", "Preencha o <b>anfitrião</b> (p. ex. <code>192.168.1.20</code>), a <b>partilha</b> (p. ex. <code>photo</code>), uma <b>pasta</b> opcional, e o seu <b>nome de utilizador</b> e <b>palavra-passe</b>. A palavra-passe fica guardada na Keychain do iOS ou no Keystore do Android.", "Toque em <b>Testar ligação</b>: uma mensagem confirma a ligação e quantos elementos foram encontrados. Depois <b>Salvar</b>."]),
        ("p", "O NAS aparece agora no separador Backup com o seu espaço livre. Pode copiar <b>fora de casa</b> se o NAS for acessível — o modo mais simples e seguro é uma VPN como o <b>Tailscale</b>: instale-o no NAS e no telemóvel e use o endereço <code>100.x.x.x</code> do NAS como anfitrião."),
        ("note", "Com dados móveis, um aviso laranja alerta que os vídeos grandes podem gastar muitos dados; <b>Parar</b> interrompe a cópia (fica marcada como Parcial)."),
    ]),
    ("android", "Android e iPhone: o que difere", [
        ("p", "As duas aplicações partilham o mesmo motor: mesma deteção de duplicados, mesmos nomes, mesma verificação SHA-256, mesmo índice — uma cópia iniciada numa é reconhecida pela outra."),
        ("table", ["", "iPhone / iPad", "Android"], [
            ["Fonte da biblioteca", "Biblioteca de Fotos", "Galeria (fotos e vídeos)"],
            ["Destino", "Pasta escolhida em Ficheiros (SSD, iCloud Drive, SMB)", "Pasta escolhida com o seletor do sistema (SSD, USB, armazenamento do telemóvel), NAS"],
            ["Segundo plano", "Cerca de 30 segundos; depois o ecrã fica aceso durante a cópia", "Uma notificação em primeiro plano mantém-na ativa, com botão Parar"],
            ["Pro", "Compra na aplicação (App Store)", "Compra única (Google Play)"],
            ["Mac", "Funciona em Macs com chip Apple («concebida para iPad»)", "—"],
        ]),
        ("note", "No Android, um destino no armazenamento interno do telemóvel é escondido da galeria (um ficheiro <code>.nomedia</code>) para que a cópia não seja copiada de novo."),
        ("fig", "android_backup", "Android: o separador Backup."),
        ("fig", "android_settings", "Android: Definições."),
    ]),
    ("faq", "Perguntas frequentes", [
        ("p", "<b>Vai copiar duas vezes o mesmo ficheiro se eu executar de novo?</b> Não. Cada ficheiro recebe um nome no destino e a cópia seguinte procura-o com esse nome. Se os registos da aplicação mostrarem que veio do mesmo original, é ignorado — mesmo que o tenha editado entretanto. Só ficheiros realmente diferentes com o mesmo nome recebem um sufixo <code>-1</code>, <code>-2</code>…, e nunca se substitui nada."),
        ("p", "<b>Onde guarda a aplicação a memória do que copiou?</b> Na sua própria base de dados e num pequeno <b>ficheiro oculto, <code>.pvb-index.json</code>, na raiz de cada destino</b>. Essa cópia viaja com a cópia de segurança: após uma reinstalação, ou a partir de outro telemóvel, a aplicação lê-a e não copia de novo. Pode deixá-la em paz; se a apagar, a aplicação reconstrói-a."),
        ("p", "<b>Posso copiar para um NAS e para uma unidade ao mesmo tempo?</b> Sim — cada destino ligado recebe a cópia em simultâneo."),
        ("p", "<b>A ligação ao meu NAS expira.</b> Normalmente o NAS não está acessível: verifique se está na mesma rede Wi-Fi (ou se a VPN está ativa), se a partilha SMB está ativada e se a firewall do NAS permite a ligação."),
        ("p", "<b>Posso usar dois telemóveis com a mesma unidade?</b> Sim. Dê a cada um um nome de pasta diferente nas Definições; cada um cria a sua própria pasta na unidade."),
        ("p", "<b>A barra indica 3 % e parece bloqueada.</b> Os primeiros ficheiros são muitas vezes vídeos grandes. Aguarde alguns minutos."),
        ("p", "<b>O meu cartão aparece como «Documents».</b> Algumas câmaras usam uma pasta genérica. Escreva um nome significativo ao adicionar a fonte."),
        ("p", "<b>Posso copiar com o telemóvel quase cheio?</b> Sim. Os ficheiros são enviados em fluxo para o destino, por isso só se retêm alguns megabytes de cada vez. Só uma cópia para um NAS <i>sozinho</i> precisa de espaço para um ficheiro de cada vez. Um ficheiro que realmente não cabe é assinalado como falhado e o resto continua."),
        ("p", "<b>Os meus dados são enviados para algum lado?</b> Não. Tudo se passa entre o seu telemóvel e a sua unidade ou NAS. A aplicação não tem servidor nem conta. O único tráfego de rede vai para o NAS que configura e para a transferência, pelo sistema, das suas próprias fotos do iCloud / Google."),
        ("p", "<b>Que idiomas?</b> Inglês, francês, alemão, espanhol, italiano, português, chinês simplificado e russo. A aplicação segue o idioma do telemóvel; pode forçar um em <b>Definições → Idioma</b>, sem reiniciar."),
    ]),
]

PRIVACY = {
    "title": "Política de privacidade — PhotoVideoBackup",
    "updated": "Última atualização: {date}",
    "summary": "O PhotoVideoBackup não recolhe, armazena, transmite nem partilha quaisquer dados pessoais. Não há conta, nem análise, nem publicidade, nem servidor próprio.",
    "sections": [
        ("A que a aplicação acede", [
            ("ul", ["Às suas fotos e vídeos — em <b>só de leitura</b>, para os copiar para a unidade, pasta ou NAS que escolher. No Android inclui a localização guardada nas fotos, para que a cópia seja idêntica ao original.", "Às pastas e cartões que escolhe com o explorador de ficheiros do sistema.", "Às notificações, para o avisar quando uma cópia termina."]),
        ]),
        ("O que sai do seu dispositivo", [
            ("ul", ["<b>Nada chega até nós.</b> Os seus ficheiros só são escritos nos destinos que escolher.", "Se configurar um NAS, a aplicação liga-se a <b>esse servidor</b>, no endereço que introduziu, e a mais nenhum lado. A palavra-passe fica guardada na Keychain do iOS ou no Keystore do Android.", "O iOS ou o Android pode transferir as suas próprias fotos do iCloud ou do Google para que a aplicação as leia; é o sistema que o faz, para a sua conta.", "As compras são tratadas pela Apple ou pela Google. Não recebemos qualquer informação de pagamento."]),
        ]),
        ("Registo de diagnóstico", [
            ("p", "A aplicação guarda no seu dispositivo um pequeno registo de diagnóstico, sem conteúdo pessoal. Só é enviado se decidir enviá-lo por e-mail ao suporte a partir da aplicação."),
        ]),
        ("Contacto com o suporte", [
            ("p", "Se escrever ao suporte, recebemos o que enviar — o seu endereço e a sua mensagem — e só o usamos para lhe responder."),
        ]),
    ],
}
