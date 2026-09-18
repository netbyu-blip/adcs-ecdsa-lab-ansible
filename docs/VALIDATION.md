# Validation du contenu (ce qui a été vérifié, et comment)

**Rédigé par :** ukestr Analyst  
**Date :** 2026-09-18  
**Version :** 1.0

Ce dépôt a été écrit sans accès à un vCenter ni à des VM Windows. Les éléments
suivants ont été validés avant publication ; le reste est à confirmer au premier
run (voir `PLAN-DE-TEST.md`, T01 à T06).

## Syntaxe

- `ansible-playbook --syntax-check` sur `site.yml` et `repro.yml` avec
  community.vmware 4.1.0, ansible.windows 3.6.1, community.windows 2.1.0,
  microsoft.ad 1.4.1.
- Noms de paramètres de chaque module vérifiés avec `ansible-doc`
  (`vmware_guest`, `vmware_guest_file_operation`, `vmware_vm_shell`,
  `vmware_guest_tools_wait`, `win_hosts`, `win_powershell`, `win_certificate_store`,
  `win_iis_webbinding`, `win_dns_record`, `win_dns_client`, `microsoft.ad.domain`,
  `microsoft.ad.membership`).
- Les 13 scripts PowerShell inline (rendus avec les variables de `group_vars`)
  et les 2 fichiers `.ps1` passent le parseur PowerShell 7.6 sans erreur, et
  PSScriptAnalyzer (Warning+Error) sans finding bloquant.

## Sémantique, contre la documentation Microsoft

| Élément | Source |
|---|---|
| `Install-AdcsCertificationAuthority` : `-CAType` (4 valeurs), `-CryptoProviderName "ECDSA_P256#Microsoft Software Key Storage Provider"`, `-KeyLength 256`, `-HashAlgorithmName SHA256`, `-OutputCertRequestFile`, pas de `-ValidityPeriod` pour une subordonnée ; Enterprise Admins requis pour une CA d'entreprise | [ADCSDeployment](https://learn.microsoft.com/en-us/powershell/module/adcsdeployment/install-adcscertificationauthority) |
| `certreq -submit -config -` (CA locale), fichiers `certfileout certchainfileout`, `-q`, clés INF `KeyAlgorithm=ECDSA_P256`, `KeyUsage=0x80`, `[RequestAttributes] CertificateTemplate`, SAN `2.5.29.17 = "{text}"` + `_continue_ = "DNS=...&"` | [certreq](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/certreq_1) |
| `certutil -dspublish -f CertFile RootCA`, `-installCert`, `-setreg`, `-pulse` (autoenrollment client, pas cache CA, d'où le `Restart-Service certsvc` dans le script de modèle) | [certutil](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/certutil) |
| Modèle : `flags` = 0x40 MACHINE_TYPE, 0x200 ADD_TEMPLATE_NAME, 0x20000 IS_MODIFIED (0x10000 IS_DEFAULT réservé aux modèles intégrés) | [MS-CRTD flags](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-crtd/6cc7eb79-3e84-477a-b398-b0ff2b68a6c0) |
| `msPKI-Private-Key-Flag` : masques 0x000F0000 (CA) et 0x0F000000 (client), 0x4 = 2012 / Windows 8 ; 0x40 = REQUIRE_ALTERNATE_SIGNATURE_ALGORITHM (non positionné) | [MS-CRTD](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-crtd/f6122d87-b999-4b92-bff8-f465e8949667), [MS-WCCE](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-wcce/ef03f3b9-d089-4152-96a4-e14b5c5a4ab1) |
| `msPKI-RA-Application-Policies` en triplets `` Nom`Type`Valeur` `` (`msPKI-Asymmetric-Algorithm`, `msPKI-Hash-Algorithm`, `msPKI-Key-Usage` DWORD 2 = signature) | [MS-CRTD Syntax Option 2](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-crtd/c55ec697-be3f-4117-8316-8895e4399237) |
| `pKIExpirationPeriod` / `pKIOverlapPeriod` : FILETIME négatifs little-endian, recalculés (365 j, 42 j) et identiques aux exports du module ADCSTemplate | calcul + [ADCSTemplate](https://github.com/GoateePFE/ADCSTemplate) |
| Génération de l'OID de modèle (conteneur `CN=OID`, objet `msPKI-Enterprise-Oid`, `flags=1`) | [ADCSTemplate](https://github.com/GoateePFE/ADCSTemplate) `New-TemplateOID` |
| `dsacls <DN> /G "DOM\Groupe:CA;Enroll"` (CA = control access, droit étendu nommé) | [dsacls](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2012-r2-and-2012/cc771151(v=ws.11)) |
| `AlternateSignatureAlgorithm` = 1 produit une signature « discrete » (specifiedECDSA / RSASSA-PSS) | [certreq](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/certreq_1), [U. Gradenegger](https://www.gradenegger.eu/en/change-the-signature-algorithm-of-a-certification-authority-hierarchy-without-issuing-new-certification-authority-certificates/) |

## Non vérifié (à confirmer au premier run)

- Le comportement exact de `Install-AdcsCertificationAuthority -OutputCertRequestFile`
  sous WinRM + become runas (double saut résolu par le logon interactif).
- La création du modèle par ADSI en deux `SetInfo` : méthode répandue, mais le
  module ADCSTemplate passe par `New-ADObject` en un seul appel. En cas d'échec,
  `certtmpl.msc` sur SUBCA permet de comparer avec un modèle dupliqué à la main.
- Edge headless sous une session WinRM : indicatif seulement.

---

Rédigé et signé par **ukestr Analyst**, le 2026-09-18.
