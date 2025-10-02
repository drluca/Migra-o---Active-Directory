# ======== VERIFICAÇÃO DE PERMISSÕES ADMINISTRATIVAS ========
If (-NOT ([System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator))
{
    Write-Host "Este script não está sendo executado com permissões administrativas."
    Write-Host "Solicitando elevação de permissões..."
    
    # Reinicia o script com permissões de administrador
    $arguments = "& '" + $myinvocation.MyCommand.Definition + "'"
    Start-Process powershell -ArgumentList $arguments -Verb runAs
    Exit
}

Write-Host "Permissões administrativas concedidas. Continuando o script..."

# ======== CONFIGURAÇÃO DE DNS ========
$dnsPrimario = "DNS AQUI"     
$dnsSecundario = "DNS AQUI"   

# ======== CREDENCIAIS ADMINISTRATIVAS PARA ALTERAÇÃO DE DNS ========
$dnsAdminUsuario = "DOMINIOATUAL\USERADMIN"
$dnsAdminSenha = "SENHA ADMIN"  # Senha com caracteres especiais e números
$secureDnsSenha = ConvertTo-SecureString $dnsAdminSenha -AsPlainText -Force
$credDNS = New-Object System.Management.Automation.PSCredential ($dnsAdminUsuario, $secureDnsSenha)

# ======== VERIFICAR CONEXÃO DE REDE ========
Write-Output "Verificando conectividade com o servidor DNS..."
$pingResult = Test-Connection -ComputerName $dnsPrimario -Count 1 -Quiet
if ($pingResult) {
    Write-Output "Conexão com o servidor DNS $dnsPrimario bem-sucedida."
} else {
    Write-Error "Falha ao conectar-se ao servidor DNS $dnsPrimario. Verifique a rede."
    Stop-Transcript
    Read-Host -Prompt "Pressione qualquer tecla para sair..."  # Pausa para erro
    exit
}

# ======== ALTERAR DNS ========
$adapters = Get-NetAdapter | Where-Object {$_.Status -eq "Up"}

foreach ($adapter in $adapters) {
    Write-Output "Verificando configurações de DNS do adaptador $($adapter.Name)..."
    $currentDns = Get-DnsClientServerAddress -InterfaceAlias $adapter.Name

    if ($currentDns.ServerAddresses -contains $dnsPrimario) {
        Write-Output "O adaptador $($adapter.Name) já está configurado com o DNS primário $dnsPrimario. Nenhuma alteração necessária."
    } else {
        Write-Output "Alterando DNS do adaptador $($adapter.Name)..."
        try {
            # Atualizando as configurações de DNS diretamente
            if ($dnsSecundario) {
                Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses ($dnsPrimario, $dnsSecundario)
            } else {
                Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses $dnsPrimario
            }
            Write-Output "DNS do adaptador $($adapter.Name) alterado com sucesso."
        } catch {
            Write-Error ("Falha ao alterar DNS do adaptador $($adapter.Name): " + $_.Exception.Message)
            Read-Host -Prompt "Pressione qualquer tecla para sair..."  # Pausa para erro
            exit
        }
    }
}

Write-Output "Alteração de DNS concluída!"

# ======== MIGRAÇÃO PARA O NOVO DOMÍNIO ========
$currentDomain = (Get-CimInstance -ClassName Win32_ComputerSystem).Domain
$novoDominio = "NOVO AD OU DOMINIO"  # Novo domínio

if ($currentDomain -ne $novoDominio) {
    Write-Output "O computador não está no domínio $novoDominio. Iniciando a migração..."

    # Pergunta ao usuário se quer manter o nome atual ou alterar antes de prosseguir (única tela de entrada)
    $op = Read-Host "Escolha: Digite 1 para manter a nomenclatura atual ou 2 para alterar o nome do computador"

    while ($op -ne '1' -and $op -ne '2') {
        Write-Host "Opção inválida. Digite 1 para manter a nomenclatura atual ou 2 para alterar."
        $op = Read-Host "Escolha: Digite 1 para manter a nomenclatura atual ou 2 para alterar o nome do computador"
    }

    if ($op -eq '1') {
        $nomeAtual = $env:COMPUTERNAME
        Write-Output "Mantendo nome atual: $nomeAtual"
    } else {
        # Loop para validar o novo nome do computador
        do {
            $novoNome = Read-Host "Digite o novo nome do computador (sem espaços, máximo 15 caracteres)"
            if (-not $novoNome) {
                Write-Host "Nome inválido. Não pode ser vazio. Tente novamente.`n"
                continue
            }
            if ($novoNome.Length -gt 15) {
                Write-Host "Nome muito longo (máx 15 caracteres). Tente novamente.`n"
                continue
            }
            if ($novoNome -match '[^A-Za-z0-9\-]') {
                Write-Host "Caracteres inválidos detectados. Use apenas letras, números e '-' (hífen). Tente novamente.`n"
                continue
            }
            # Se chegou aqui, nome válido
            break
        } while ($true)

        $nomeAtual = $novoNome
        Write-Output "Nome definido para: $nomeAtual"
    }

    # CREDENCIAIS PARA MIGRAÇÃO DE DOMÍNIO
    $dominioAdminUsuario = "DOMINIONOVO\USERADMIN"
    $dominioAdminSenha = "SENHA ADMIN"  # Senha do novo domínio
    $secureDomSenha = ConvertTo-SecureString $dominioAdminSenha -AsPlainText -Force
    $credDominio = New-Object System.Management.Automation.PSCredential ($dominioAdminUsuario, $secureDomSenha)

    try {
        # Adiciona o computador ao novo domínio
        Add-Computer -DomainName $novoDominio -Credential $credDominio -NewName $nomeAtual -Force
        Write-Output "Migração para o domínio $novoDominio realizada com sucesso."
    } catch {
        Write-Error ("Falha ao migrar o computador para o domínio ${novoDominio} " + $_.Exception.Message)
        Read-Host -Prompt "Pressione qualquer tecla para sair..."  # Pausa para erro
        exit
    }
} else {
    Write-Output "O computador já está no domínio $novoDominio. Nenhuma migração necessária."
}

# ======== FINALIZAÇÃO ========
Write-Output "Processo concluído com sucesso!"

# Tela final para decidir o reinício
$reiniciar = Read-Host "Deseja reiniciar o computador agora? (Digite 'SIM' para reiniciar ou 'NAO' para reiniciar depois)"

if ($reiniciar -match '^[Ss]im$') {
    Write-Host "Reiniciando o computador..."
    Restart-Computer -Force
} else {
    Write-Host "Reinício adiado. Você pode reiniciar o computador mais tarde."
}

# Forçar a atualização das políticas de grupo após reiniciar
Start-Sleep -Seconds 30  # Aguarda 30 segundos após o reinício para garantir que o sistema tenha tempo para inicializar
Write-Host "Atualizando as políticas de grupo..."
gpupdate /force

# Pausa final para garantir que a execução seja concluída corretamente
Read-Host -Prompt "Pressione qualquer tecla para sair..."  # Pausa final
