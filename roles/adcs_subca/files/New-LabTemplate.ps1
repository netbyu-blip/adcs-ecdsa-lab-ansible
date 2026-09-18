# Crée un modèle de certificat v4 ECDSA P-256 / SHA-256 (type "Web Server", sujet fourni
# dans la requête) directement dans AD via ADSI, puis le publie sur la CA locale.
# À exécuter avec un compte Enterprise Admins (become runas interactif).
param(
    [string]$Name,
    [string]$DisplayName,
    [string]$CAName
)
$ErrorActionPreference = 'Stop'
$changed = $false

$configNC  = ([ADSI]'LDAP://RootDSE').configurationNamingContext
$pksDN     = "CN=Public Key Services,CN=Services,$configNC"
$tplDN     = "CN=Certificate Templates,$pksDN"
$tplPath   = "LDAP://CN=$Name,$tplDN"

if (-not [ADSI]::Exists($tplPath)) {
    # 1. OID du modèle dans le conteneur OID de la forêt (même méthode que le module ADCSTemplate)
    $oidContainer = [ADSI]"LDAP://CN=OID,$pksDN"
    $forestOid    = $oidContainer.Get('msPKI-Cert-Template-OID')
    do {
        $p1 = Get-Random -Minimum 1000000 -Maximum 99999999
        $p2 = Get-Random -Minimum 1000000 -Maximum 99999999
        $p3 = -join ((1..32) | ForEach-Object { '{0:X}' -f (Get-Random -Maximum 16) })
        $templateOid = "$forestOid.$p1.$p2"
        $oidCn       = "$p2.$p3"
    } while ([ADSI]::Exists("LDAP://CN=$oidCn,CN=OID,$pksDN"))

    $oidObj = $oidContainer.Create('msPKI-Enterprise-Oid', "CN=$oidCn")
    $oidObj.Put('msPKI-Cert-Template-OID', $templateOid)
    $oidObj.Put('flags', 1)
    $oidObj.Put('displayName', $DisplayName)
    $oidObj.SetInfo()

    # 2. Objet pKICertificateTemplate
    $container = [ADSI]"LDAP://$tplDN"
    $t = $container.Create('pKICertificateTemplate', "CN=$Name")
    $t.Put('distinguishedName', "CN=$Name,$tplDN")
    $t.Put('displayName', $DisplayName)
    # MS-CRTD flags : 0x40 CT_FLAG_MACHINE_TYPE | 0x200 CT_FLAG_ADD_TEMPLATE_NAME | 0x20000 CT_FLAG_IS_MODIFIED
    $t.Put('flags', 0x20240)
    $t.Put('revision', 100)
    $t.Put('pKIDefaultKeySpec', 1)
    $t.SetInfo()

    $t.Put('pKIMaxIssuingDepth', 0)
    $t.Put('pKICriticalExtensions', '2.5.29.15')
    $t.Put('pKIExtendedKeyUsage', '1.3.6.1.5.5.7.3.1')                   # Server Authentication
    $t.Put('pKIKeyUsage', [byte[]]@(0x80, 0x00))                          # digitalSignature (clé ECDSA)
    # FILETIME négatifs little-endian : -(jours * 864000000000)
    $t.Put('pKIExpirationPeriod', [byte[]]@(0, 64, 57, 135, 46, 225, 254, 255))   # 365 jours
    $t.Put('pKIOverlapPeriod',    [byte[]]@(0, 128, 166, 10, 255, 222, 255, 255)) # 42 jours
    $t.Put('pKIDefaultCSPs', '1,Microsoft Software Key Storage Provider')
    $t.Put('msPKI-RA-Signature', 0)
    $t.Put('msPKI-Enrollment-Flag', 0)
    # MS-WCCE : 0x000F0000 = version CA minimale (0x4 = 2012), 0x0F000000 = version client minimale (0x4 = Windows 8)
    $t.Put('msPKI-Private-Key-Flag', 0x04040000)
    $t.Put('msPKI-Certificate-Name-Flag', 1)                             # CT_FLAG_ENROLLEE_SUPPLIES_SUBJECT
    $t.Put('msPKI-Minimal-Key-Size', 256)
    $t.Put('msPKI-Template-Schema-Version', 4)
    $t.Put('msPKI-Template-Minor-Revision', 1)
    $t.Put('msPKI-Cert-Template-OID', $templateOid)
    $t.Put('msPKI-Certificate-Application-Policy', '1.3.6.1.5.5.7.3.1')
    $t.Put('msPKI-RA-Application-Policies',
        'msPKI-Asymmetric-Algorithm`PZPWSTR`ECDSA_P256`msPKI-Hash-Algorithm`PZPWSTR`SHA256`msPKI-Key-Usage`DWORD`2`msPKI-Symmetric-Algorithm`PZPWSTR`3DES`msPKI-Symmetric-Key-Length`DWORD`168`')
    $t.SetInfo()

    # 3. Droit Enroll pour les ordinateurs du domaine (Domain/Enterprise Admins ont déjà tout)
    & dsacls.exe "CN=$Name,$tplDN" /G "$env:USERDOMAIN\Domain Computers:CA;Enroll" | Out-Null
    if ($LASTEXITCODE) { throw "dsacls code $LASTEXITCODE" }
    $changed = $true
}

# 4. Publication sur la CA. Le service ne relit les modèles qu'à intervalle : on redémarre certsvc
#    pour qu'il voie le nouvel objet immédiatement.
Import-Module ADCSAdministration
if (-not (Get-CATemplate | Where-Object { $_.Name -eq $Name })) {
    $ok = $false
    for ($i = 0; $i -lt 6 -and -not $ok; $i++) {
        try { Add-CATemplate -Name $Name -Force; $ok = $true }
        catch { Restart-Service certsvc; Start-Sleep -Seconds 10 }
    }
    if (-not $ok) { throw "Add-CATemplate $Name a échoué après 6 essais" }
    Restart-Service certsvc
    $changed = $true
}

$Ansible.Changed = $changed
$Ansible.Result  = "Modèle $Name publié sur $CAName"
