# Amorce WinRM en HTTPS (certificat auto-signé) pour Ansible, machine en workgroup.
$ErrorActionPreference = 'Stop'
$log = 'C:\Windows\Temp\winrm_bootstrap.log'
Start-Transcript -Path $log -Append | Out-Null

try {
    # Le profil réseau "Public" bloque WinRM par défaut en workgroup
    Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private

    Enable-PSRemoting -Force -SkipNetworkProfileCheck

    $name = $env:COMPUTERNAME
    $cert = Get-ChildItem Cert:\LocalMachine\My |
        Where-Object { $_.Subject -eq "CN=$name" -and $_.FriendlyName -eq 'WinRM-HTTPS' } |
        Select-Object -First 1
    if (-not $cert) {
        $cert = New-SelfSignedCertificate -DnsName $name -CertStoreLocation Cert:\LocalMachine\My -FriendlyName 'WinRM-HTTPS'
    }

    $https = Get-ChildItem WSMan:\localhost\Listener | Where-Object { $_.Keys -contains 'Transport=HTTPS' }
    if (-not $https) {
        New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * -CertificateThumbPrint $cert.Thumbprint -Force | Out-Null
    }

    Set-Item WSMan:\localhost\Service\Auth\Basic     -Value $false
    Set-Item WSMan:\localhost\Service\Auth\Negotiate -Value $true

    if (-not (Get-NetFirewallRule -DisplayName 'WinRM HTTPS' -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName 'WinRM HTTPS' -Direction Inbound -Protocol TCP -LocalPort 5986 -Action Allow | Out-Null
    }

    # Comptes admin locaux via WinRM en workgroup
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' `
        -Name LocalAccountTokenFilterPolicy -Value 1 -Type DWord

    Set-Service WinRM -StartupType Automatic
    Restart-Service WinRM
    Write-Output "WinRM HTTPS prêt, empreinte $($cert.Thumbprint)"
}
finally {
    Stop-Transcript | Out-Null
}
