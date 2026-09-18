# Annexe : documents et sites de référence

**Rédigé par :** ukestr Analyst  
**Date :** 2026-09-18

Toutes les sources consultées pour l'échange du 2026-09-17 avec Luc, le lab et
la validation des commandes. Classées par thème.

## A. Migration RSA vers ECDSA d'une hiérarchie AD CS

| Référence | Contenu utile |
|---|---|
| [Securing PKI: Planning Certificate Algorithms and Usages (Microsoft)](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2012-r2-and-2012/dn786428(v=ws.11)) | Ne pas mélanger RSA et ECC dans une même chaîne ; construire une hiérarchie parallèle pour changer d'algorithme ; hachage proportionné à la clé (P-256 / SHA-256). |
| [Changer la longueur de clé d'une CA, incluant ECDSA (blog support Microsoft Japon)](https://jpwinsup.github.io/blog/2025/05/07/PublicKeyInfrastructure/CertificateAuthority/ca-change-key-length/) | Procédure `CAPolicy.inf` `RenewalKeyLength` + `certutil -setreg ca\csp\CNGPublicKeyAlgorithm ECDSA_PXXX` avant renouvellement avec nouvelle clé. |
| [Renew CA Certificate with different signing algorithm (Microsoft Q&A)](https://learn.microsoft.com/en-us/answers/questions/2192904/renew-ca-certificate-with-different-signing-algori) | Renouvellement à clé identique après `certutil -setreg ca\csp\CNGHashAlgorithm SHA256`. |
| [Renew root CA certificate in Windows Server (Microsoft Learn)](https://learn.microsoft.com/en-us/windows-server/identity/ad-cs/renew-root-ca-certificate) | Procédure officielle de renouvellement du certificat racine. |
| [How to migrate AD CS to SHA-2 and Key Storage Provider (4sysops)](https://4sysops.com/archives/how-to-migrate-active-directory-certificate-services-to-sha-2-and-key-storage-provider/) | Migration d'une clé de CSP hérité vers KSP, prérequis à tout changement d'algorithme CNG. |
| [Which key lengths should be used for CAs and certificates (U. Gradenegger)](https://www.gradenegger.eu/en/which-key-sizes-should-be-used-for-certification-bodies-and-certificates/) | Recommandations de tailles de clés. |
| [Basics: Key algorithms, signature algorithms and signature hash algorithms (U. Gradenegger)](https://www.gradenegger.eu/en/basics-key-algorithms-signature-algorithms-and-signature-hash-algorithms/) | Distinction algorithme de clé / de signature / de hachage. |
| [The key algorithm of certificate requests is not checked by the policy module (U. Gradenegger)](https://www.gradenegger.eu/en/key-algorithm-is-not-checked-by-the-policy-module/) | La CA vérifie la taille de clé du modèle, pas l'algorithme. |

## B. Rejet Chromium et signature specifiedECDSA (AlternateSignatureAlgorithm)

| Référence | Contenu utile |
|---|---|
| [Change the signature algorithm of a CA hierarchy without issuing new CA certificates (U. Gradenegger)](https://www.gradenegger.eu/en/change-the-signature-algorithm-of-a-certification-authority-hierarchy-without-issuing-new-certification-authority-certificates/) | Passage `AlternateSignatureAlgorithm` 1 → 0, re-signature avec `certutil -sign`, `certutil -repairstore`, `CACertHash`. |
| [certreq (Microsoft Learn)](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/certreq_1) | Clé INF `AlternateSignatureAlgorithm` : signature « discrete » vs combinée ; syntaxe `-new`, `-submit`, `-accept`, `-config -`, SAN. |
| [Chromium: net::ERR_CERT_INVALID avec paramètres ECDSA (phpseclib, issue 2051)](https://github.com/phpseclib/phpseclib/issues/2051) | Chromium refuse les paramètres dans l'AlgorithmIdentifier d'une signature ECDSA. |
| [NET::ERR_CERT_INVALID in Chrome but not in Edge (Chrome Enterprise community)](https://support.google.com/chrome/a/thread/185950857/net-err-cert-invalid-in-chrome-but-not-in-edge-chromium?hl=en) | Différences de validation entre navigateurs Chromium. |
| [certutil (Microsoft Learn)](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/certutil) | `-dspublish`, `-installCert`, `-setreg`, `-pulse`, `-verify -urlfetch`, `-dump`. |

## C. Modèles de certificats et Active Directory (validation du script de modèle)

| Référence | Contenu utile |
|---|---|
| [MS-CRTD : flags Attribute](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-crtd/6cc7eb79-3e84-477a-b398-b0ff2b68a6c0) | 0x40 MACHINE_TYPE, 0x200 ADD_TEMPLATE_NAME, 0x10000 IS_DEFAULT, 0x20000 IS_MODIFIED. |
| [MS-CRTD : msPKI-Private-Key-Flag Attribute](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-crtd/f6122d87-b999-4b92-bff8-f465e8949667) | Drapeaux de clé privée, masques de compatibilité 0x000F0000 / 0x0F000000, 0x40 REQUIRE_ALTERNATE_SIGNATURE_ALGORITHM. |
| [MS-WCCE : msPKI-Private-Key-Flag (règles de traitement)](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-wcce/ef03f3b9-d089-4152-96a4-e14b5c5a4ab1) | Comportement de la CA selon la version minimale encodée. |
| [MS-CRTD : msPKI-RA-Application-Policies, Syntax Option 2](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-crtd/c55ec697-be3f-4117-8316-8895e4399237) | Triplets `` Nom`Type`Valeur` `` : `msPKI-Asymmetric-Algorithm`, `msPKI-Hash-Algorithm`, `msPKI-Key-Usage`. |
| [MS-CRTD : Structure Example](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-crtd/11f578e0-15ff-4d2c-86bb-206c50153d89) | Exemple complet d'objet `pKICertificateTemplate`. |
| [MS-ADSC : Class pKICertificateTemplate](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-adsc/db4b45f7-e57a-4ae1-9b8f-1b107b69d98c) | Schéma de la classe. |
| [ADCSTemplate, module PowerShell (GoateePFE / Microsoft)](https://github.com/GoateePFE/ADCSTemplate) | Génération de l'OID de modèle (`New-TemplateOID`), création par `New-ADObject`, publication, ACL ; exemple `PowerShellCMS.json`. |
| [Reading an AD Certificate Template: Every Attribute, Explained (BrkrOps)](https://brkrops.ca/blog/reading-ad-certificate-template-attributes/) | Correspondance des nibbles de compatibilité avec les versions Windows. |
| [ad_cs_certificate_template, rôle Ansible (FuxMak)](https://github.com/FuxMak/ad_cs_certificate_template) | Autre implémentation Ansible de création de modèles. |
| [dsacls (Microsoft Learn)](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2012-r2-and-2012/cc771151(v=ws.11)) | Syntaxe `/G "DOM\Groupe:CA;Enroll"`. |

## D. Installation AD CS et PowerShell

| Référence | Contenu utile |
|---|---|
| [Install-AdcsCertificationAuthority (ADCSDeployment)](https://learn.microsoft.com/en-us/powershell/module/adcsdeployment/install-adcscertificationauthority) | Paramètres `-CAType`, `-CryptoProviderName "ECDSA_P256#Microsoft Software Key Storage Provider"`, `-KeyLength`, `-HashAlgorithmName`, `-OutputCertRequestFile`, droits requis. |
| [PowerShell (GitHub, releases)](https://github.com/PowerShell/PowerShell/releases) | Version portable utilisée pour le parseur (7.6.6). |
| [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer) | Analyse statique des scripts. |

## E. Ansible et VMware

| Référence | Contenu utile |
|---|---|
| [community.vmware (collection Ansible)](https://github.com/ansible-collections/community.vmware) | `vmware_guest` (clone, customisation Windows, réseau statique), `vmware_vm_shell`, `vmware_guest_file_operation`, `vmware_guest_tools_wait`. |
| [ansible.windows (collection Ansible)](https://github.com/ansible-collections/ansible.windows) | `win_powershell`, `win_feature`, `win_certificate_store`, `win_hosts`, `win_dns_client`, `win_regedit`, `win_uri`. |
| [community.windows (collection Ansible)](https://github.com/ansible-collections/community.windows) | `win_iis_webbinding`, `win_firewall_rule`, `win_dns_record`. |
| [microsoft.ad (collection Ansible)](https://github.com/ansible-collections/microsoft.ad) | `microsoft.ad.domain`, `microsoft.ad.membership`, remplaçants des anciens `win_domain*`. |
| [Ansible : Windows Remote Management (WinRM, become runas, double saut)](https://docs.ansible.com/ansible/latest/os_guide/windows_winrm.html) | Configuration WinRM HTTPS, limites NTLM et contournement du double saut par `become: runas`. |

## F. Alternatives et contexte général

| Référence | Contenu utile |
|---|---|
| [Modernizing your internal PKI: from Microsoft AD CS to EJBCA (Keyfactor)](https://docs.keyfactor.com/solution-areas/latest/modernizing-your-internal-pki-from-microsoft-adcs-) | Approche « nouvelle hiérarchie » vue par un éditeur tiers. |
| [Migrate from Microsoft AD CS (Smallstep)](https://smallstep.com/blog/migrate-from-microsoft-adcs/) | Idem. |
| [Step by step guide of AD CS two-tier PKI hierarchy deployment (Encryption Consulting)](https://www.encryptionconsulting.com/adcs-two-tier-pki-hierarchy-deployment/) | Déploiement de référence racine hors ligne + sous-CA d'entreprise. |
| [NIST SP 800-57 Part 1, Recommendation for Key Management](https://csrc.nist.gov/publications/detail/sp/800-57-part-1/rev-5/final) | Équivalences de force RSA / ECC citées par le guide Microsoft. |

---

Rédigé et signé par **ukestr Analyst**, le 2026-09-18.
