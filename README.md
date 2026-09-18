# Lab AD CS ECDSA P-256 sur vSphere (Ansible)

Déploie quatre VM Windows sur vCenter, puis construit une PKI à deux niveaux en
ECDSA P-256 / SHA-256 avec une CA subordonnée d'entreprise :

| VM     | Rôle                                                                        | IP          |
|--------|-----------------------------------------------------------------------------|-------------|
| DC01   | AD DS + DNS, forêt `lab.local` (NetBIOS `LAB`)                              | 10.10.10.5  |
| ROOTCA | CA racine autonome hors domaine, éteinte à la fin (`-t root_offline`)       | 10.10.10.10 |
| SUBCA  | CA subordonnée d'entreprise, modèle ECDSA, Web Enrollment, IIS, feuille     | 10.10.10.20 |
| CLIENT | Poste de test membre du domaine (Edge + validation CryptoAPI)               | 10.10.10.30 |

`pki_issuing_ca_type: StandaloneSubordinateCA` dans `group_vars/all.yml` revient
au mode autonome (le DC et la jonction restent, le modèle n'est pas créé).

Le but est de reproduire l'erreur `NET::ERR_CERT_INVALID` de Edge/Chromium quand
la CA signe avec l'OID générique `specifiedECDSA` (1.2.840.10045.4.3) au lieu de
`sha256ECDSA` (1.2.840.10045.4.3.2), ce qui arrive avec
`AlternateSignatureAlgorithm=1`.

## Prérequis

- vCenter accessible depuis le contrôleur Ansible, un port group isolé (`LAB-PKI`).
- Un template Windows Server 2022/2025 Evaluation (Desktop Experience, VMware
  Tools installés, **non** sysprepé : la customisation vSphere lance sysprep
  elle-même). Le même template peut servir pour le client, Edge est inclus.
  Un template Windows 11 Enterprise Evaluation fonctionne aussi pour CLIENT.
- Sur le contrôleur :

```bash
python3 -m pip install ansible pyvmomi pywinrm
ansible-galaxy collection install -r requirements.yml
```

  Les modules AD viennent de `microsoft.ad` (les anciens `win_domain*` ont été
  retirés d'`ansible.windows` 3.x).

- Secrets :

```bash
cp inventory/group_vars/vault.yml.example inventory/group_vars/vault.yml
ansible-vault encrypt inventory/group_vars/vault.yml
```

- Adapter `inventory/group_vars/all.yml` (vCenter, datastore, templates, réseau).

## Déroulement

```bash
# 1. Cloner les 4 VM, customisation (hostname, IP, mot de passe), bootstrap WinRM HTTPS via VMware Tools
ansible-playbook site.yml --ask-vault-pass -t provision

# 2. Domaine : promotion de DC01, enregistrements DNS, jonction de SUBCA et CLIENT
ansible-playbook site.yml --ask-vault-pass -t common,dc,join

# 3. PKI : racine, sous-CA d'entreprise + modèle ECDSA + Web Enrollment, feuille IIS, client
ansible-playbook site.yml --ask-vault-pass -t rootca,subca,leaf,client

# 4. Éteindre la racine
ansible-playbook site.yml --ask-vault-pass -t root_offline
```

Ou tout d'un coup : `ansible-playbook site.yml --ask-vault-pass`.

À la fin, le play `client` affiche :

- l'algorithme de signature de la feuille (attendu `sha256ECDSA`),
- le résultat d'un `Invoke-WebRequest` côté CryptoAPI (côté « IE »),
- le code `ERR_CERT_*` trouvé par Edge headless, s'il y en a un.

Prenez un snapshot des trois VM à ce stade (« état sain »).

## Reproduire l'erreur Edge

```bash
# Feuille signée en specifiedECDSA -> Edge : NET::ERR_CERT_INVALID, CryptoAPI : OK
ansible-playbook repro.yml --ask-vault-pass -e subca_alternate_signature_algorithm=1

# Retour à la normale
ansible-playbook repro.yml --ask-vault-pass -e subca_alternate_signature_algorithm=0
```

`repro.yml` change la valeur registre `CA\CSP\AlternateSignatureAlgorithm` sur
la sous-CA, redémarre `certsvc`, réémet le certificat feuille, refait le binding
IIS et relance les tests côté client.

Variante « toute la chaîne cassée » : restaurer les snapshots d'avant PKI, puis
`ansible-playbook site.yml -t rootca,subca,leaf,client -e rootca_alternate_signature_algorithm=1`.
Le certificat de la sous-CA est alors lui aussi signé en `specifiedECDSA`.

## Documentation

- [`docs/PLAN-DE-TEST.md`](docs/PLAN-DE-TEST.md) : cas de test T01 à T12, attendus, matrice de résultats, transposition en production.
- [`docs/VALIDATION.md`](docs/VALIDATION.md) : ce qui a été vérifié avant publication (syntaxe, doc Microsoft) et ce qui reste à confirmer.

## Vérification manuelle

Sur CLIENT, dans Edge : `https://www.lab.local`. Côté CryptoAPI :

```
certutil -verify -urlfetch C:\ProgramData\lab\www.cer
certutil -v -dump C:\ProgramData\lab\www.cer | findstr ObjectId
```

Web Enrollment : `http://subca.lab.local/certsrv` (la sous-CA émet
automatiquement, `Policy\RequestDisposition=1`).

## Partie Active Directory

- `roles/win_dc` : AD DS + DNS, `microsoft.ad.domain` (redémarrage géré par le
  module), enregistrements A `rootca`, `pki`, `www` dans `lab.local`.
- `roles/win_domain_join` : client DNS vers DC01 puis `microsoft.ad.membership`.
  Ce play se connecte avec le compte Administrator local ; ensuite les
  group_vars de `domain_members` utilisent `LAB\Administrator` avec
  `become: runas` (logon interactif). C'est ce qui évite le double saut NTLM
  quand SUBCA doit écrire dans AD (installation de la CA d'entreprise,
  `certutil -dspublish`, création du modèle).
- `roles/adcs_subca/files/New-LabTemplate.ps1` : crée par ADSI un modèle v4
  `LabWebServerECDSA` (ECDSA P-256, SHA-256, taille minimale 256, sujet fourni
  dans la requête, EKU Server Authentication, Enroll pour Domain Computers),
  génère son OID dans le conteneur OID de la forêt et le publie avec
  `Add-CATemplate`. Le modèle Web Server intégré exige 2048 bits et refuserait
  une clé P-256.
- La racine est publiée dans AD (`certutil -dspublish -f ... RootCA`), les
  membres du domaine la reçoivent aussi par autoenrollment ; le client l'importe
  quand même localement pour ne pas dépendre du délai de GPO.

## Notes

- Lab uniquement : `validate_certs: false` vers vCenter, WinRM HTTPS auto-signé,
  comptes Administrator, mot de passe DSRM dans le vault.
- Les fichiers échangés entre CA transitent par `artifacts/` sur le contrôleur.
- Le test Edge headless est un indicateur ; la référence reste Edge ouvert à la main.

## Auteur

Documentation et plan de test rédigés par **ukestr Analyst** (2026-09-18).
