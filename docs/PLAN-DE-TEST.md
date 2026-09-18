# Plan de test : PKI AD CS ECDSA P-256 et rejet Chromium (specifiedECDSA)

**Rédigé par :** ukestr Analyst  
**Date :** 2026-09-18  
**Version :** 1.0

## 0. Contexte

Ce plan découle d'un échange du 2026-09-17 avec Luc, collègue en charge de la PKI,
qui a posé les questions dans l'ordre suivant :

1. **Rehausser une racine et une sous-CA Microsoft AD CS de RSA / SHA-256 vers
   ECDSA P-256.** Réponse retenue : Microsoft ne documente pas de conversion en
   place et recommande une hiérarchie parallèle entièrement ECDSA. Le
   renouvellement du certificat de CA avec nouvelle clé après modification de
   `CA\CSP\CNGPublicKeyAlgorithm` est techniquement possible sur un KSP CNG,
   mais non supporté officiellement.
2. **Après installation d'une racine et d'une sous-CA ECDSA fonctionnelles, un
   certificat feuille pour IIS est refusé par Microsoft Edge
   (`NET::ERR_CERT_INVALID`) mais accepté par Internet Explorer.** Luc avait
   identifié que l'algorithme de signature apparaissait comme un ECDSA
   « générique » au lieu de `sha256ECDSA`. Diagnostic : la CA signe avec l'OID
   `specifiedECDSA` (1.2.840.10045.4.3) quand `AlternateSignatureAlgorithm=1` ;
   CryptoAPI l'accepte, Chromium et les validateurs non Microsoft non.
3. **Disposer d'un bac à sable pour tester** : une racine, une sous-CA portant
   IIS et le certificat feuille, un client pour reproduire l'erreur Edge, les
   rôles Certification Authority et Web Enrollment installés.
4. Le lendemain : automatiser ce lab avec Ansible sur VMware, ajouter un
   contrôleur de domaine pour une CA d'entreprise, publier le tout sur GitHub
   sans information sensible, documenter le plan de test et valider les
   commandes PowerShell contre la documentation Microsoft.

Le présent document répond au point 3 et au plan de test demandé au point 4.
Les cas T07 à T10 reproduisent et corrigent le symptôme décrit au point 2.

## 1. Objectif

Vérifier qu'une hiérarchie AD CS à deux niveaux en ECDSA P-256 / SHA-256 émet des
certificats acceptés par tous les validateurs courants, et reproduire de façon
contrôlée le cas où Edge/Chromium refuse un certificat (`NET::ERR_CERT_INVALID`)
alors que CryptoAPI (IE, `certutil`, .NET) l'accepte.

Hypothèse testée : la CA signe avec l'OID générique `specifiedECDSA`
(1.2.840.10045.4.3, paramètres portant le hachage) au lieu de `sha256ECDSA`
(1.2.840.10045.4.3.2) lorsque `AlternateSignatureAlgorithm=1`. CryptoAPI comprend
cette forme, Chromium/BoringSSL, Firefox/NSS, OpenSSL, Java, Android et macOS non.

## 2. Environnement

| Machine | Rôle | IP |
|---|---|---|
| DC01 | AD DS + DNS `lab.local` | 10.10.10.5 |
| ROOTCA | CA racine autonome, workgroup, éteinte après émission | 10.10.10.10 |
| SUBCA | CA subordonnée d'entreprise, IIS, Web Enrollment, site `www.lab.local` | 10.10.10.20 |
| CLIENT | Membre du domaine, Edge | 10.10.10.30 |
| Contrôleur Ansible | Linux, OpenSSL (validateur tiers) | hors lab |

Prérequis : `site.yml` exécuté jusqu'au play `client` sans erreur, snapshot
« état sain » pris sur les quatre VM.

## 3. Outils de mesure

| Outil | Ce qu'il valide | Où |
|---|---|---|
| `certutil -v -dump <cert> \| findstr ObjectId` | OID de l'algorithme de signature | SUBCA, CLIENT |
| `certutil -verify -urlfetch <cert>` | chaîne, CDP/AIA, révocation côté CryptoAPI | CLIENT |
| `Invoke-WebRequest https://www.lab.local` | TLS côté .NET/Schannel (équivalent IE) | CLIENT |
| Edge (manuel) puis Edge headless `--dump-dom` | validation Chromium | CLIENT |
| `openssl x509 -text`, `openssl verify`, `openssl s_client` | validateur tiers indépendant de Windows | contrôleur |
| `pkiview.msc` | santé CDP/AIA de la hiérarchie | SUBCA |
| Journal `Microsoft-Windows-CertificationAuthority` | erreurs d'émission | SUBCA |

## 4. Cas de test

Convention : **Attendu** décrit le résultat qui valide le cas. Toute divergence est
consignée dans la matrice de la section 5 avec la sortie brute.

### T01 Provisionnement et accès

Étapes : `ansible-playbook site.yml -t provision`.
Attendu : quatre VM sous tension, `win_ping` OK sur 5986 pour chacune,
`C:\Windows\Temp\winrm_bootstrap.log` sans erreur.

### T02 Domaine et résolution de noms

Étapes : `-t common,dc,join`, puis sur CLIENT `nltest /dsgetdc:lab.local`,
`Resolve-DnsName pki.lab.local`, `Resolve-DnsName www.lab.local`.
Attendu : DC trouvé, les deux noms résolvent vers 10.10.10.20, SUBCA et CLIENT
apparaissent dans `Get-ADComputer -Filter *`.

### T03 CA racine

Étapes : `-t rootca`, puis sur le contrôleur :

```bash
openssl x509 -in "artifacts/rootca/ROOTCA_LAB Root CA.crt" -inform DER -noout -text
```

Attendu : `Public Key Algorithm: id-ecPublicKey`, `NIST CURVE: P-256`,
`Signature Algorithm: ecdsa-with-SHA256`, validité 10 ans, CDP et AIA en
`http://pki.lab.local/pki/`. Si OpenSSL affiche `Signature Algorithm: 1.2.840.10045.4.3`,
la racine est en specifiedECDSA (voir T09).

### T04 CA subordonnée

Étapes : `-t subca`, puis sur SUBCA `certutil -cainfo`, `Get-CATemplate`,
`pkiview.msc`, et depuis CLIENT `curl.exe -I http://pki.lab.local/pki/`.
Attendu : service `certsvc` démarré, type `Enterprise Subordinate CA`, modèle
`LabWebServerECDSA` listé, pkiview tout vert (CDP/AIA racine et sous-CA
joignables), certificat de sous-CA en `sha256ECDSA` (`certutil -v -dump artifacts/subca/subca.cer`).

### T05 Certificat feuille

Étapes : `-t leaf`, puis `certutil -v -dump C:\ProgramData\lab\www.cer` sur SUBCA.
Attendu :

- Subject `CN=www.lab.local`, SAN `DNS=www.lab.local`, `DNS=subca.lab.local`
- clé `ECDSA_P256`, Key Usage `Digital Signature`, EKU `Server Authentication`
- extension `Certificate Template Information` = `LabWebServerECDSA`
- `Algorithm ObjectId: 1.2.840.10045.4.3.2 sha256ECDSA`
- binding IIS 443 présent : `Get-WebBinding -Protocol https`

### T06 Validation nominale côté client

Étapes : `-t client`, puis manuellement sur CLIENT : Edge sur `https://www.lab.local`,
et depuis le contrôleur :

```bash
openssl s_client -connect 10.10.10.20:443 -servername www.lab.local \
  -CAfile <(openssl x509 -in "artifacts/rootca/ROOTCA_LAB Root CA.crt" -inform DER) </dev/null
```

Attendu : le play affiche `sha256ECDSA`, `certutil -verify` code 0,
`CryptoAPI HTTPS : OK 200`, `Edge : aucune erreur`. Edge affiche le cadenas sans
avertissement. OpenSSL : `Verify return code: 0 (ok)`.
Prendre un snapshot « état sain » ici.

### T07 Reproduction : feuille en specifiedECDSA

Étapes : `ansible-playbook repro.yml -e subca_alternate_signature_algorithm=1`.
Attendu :

| Vérification | Résultat attendu |
|---|---|
| OID de signature de la feuille | `1.2.840.10045.4.3 specifiedECDSA` |
| `certutil -verify -urlfetch` | code 0, chaîne valide |
| `Invoke-WebRequest` | HTTP 200 |
| Edge (manuel) | page d'erreur `NET::ERR_CERT_INVALID` |
| Edge headless | `ERR_CERT_INVALID` trouvé dans le DOM |
| OpenSSL `s_client` | échec de vérification, algorithme de signature non supporté |
| Certificats de CA (racine, sous-CA) | inchangés, toujours `sha256ECDSA` |

C'est le comportement observé en production : IE accepte, Edge refuse.

### T08 Retour à la normale

Étapes : `ansible-playbook repro.yml -e subca_alternate_signature_algorithm=0`.
Attendu : identique à T06. Les certificats émis pendant T07 restent en
specifiedECDSA tant qu'ils ne sont pas réémis : vérifier qu'un certificat T07
conservé de côté échoue toujours dans Edge.

### T09 Variante : toute la chaîne en specifiedECDSA

Étapes : restaurer les snapshots d'avant PKI (ou VM neuves), puis
`ansible-playbook site.yml -t rootca,subca,leaf,client -e rootca_alternate_signature_algorithm=1`.
Attendu : la racine est auto-signée en specifiedECDSA, le certificat de la
sous-CA signé par la racine l'est aussi. Edge et OpenSSL rejettent même une
feuille émise avec `subca_alternate_signature_algorithm=0`. CryptoAPI accepte tout.
Ce cas montre qu'il faut vérifier chaque maillon de la chaîne, pas seulement la feuille.

### T10 Correction d'une chaîne cassée par renouvellement à clé identique

Manuel, à partir de T09. Sur ROOTCA puis SUBCA :

```
certutil -setreg ca\csp\AlternateSignatureAlgorithm 0
```

Retirer `AlternateSignatureAlgorithm=1` de `C:\Windows\CAPolicy.inf`, puis
console Certification Authority > Renew CA Certificate > **No** (même clé), racine
d'abord, ensuite la sous-CA (requête signée par la racine). Republier la racine
(`certutil -dspublish -f <nouvelle racine> RootCA`), réémettre la feuille.
Attendu : nouveaux certificats de CA en `sha256ECDSA` avec la même clé publique
(`certutil -dump` : même `Public Key` hash), T06 repasse, les anciens certificats
de CA restent dans les magasins sans gêner.

### T11 Compatibilité clients tiers (optionnel)

Sur CLIENT installer Firefox et Chrome, importer la racine dans Firefox
(magasin séparé), tester `https://www.lab.local` en état sain et en T07.
Attendu : mêmes résultats que Edge (Chrome), Firefox affiche
`SEC_ERROR_BAD_SIGNATURE` ou équivalent en T07.

### T12 Idempotence

Relancer `ansible-playbook site.yml` complet sur un lab déjà construit.
Attendu : aucune tâche en `failed`, aucune réémission de certificat (tâche
« Émettre le certificat feuille » en `ok`, pas `changed`), CA non réinstallées.

## 5. Matrice de résultats

| ID | Date | Exécutant | Résultat | Preuve (fichier / capture) | Remarques |
|---|---|---|---|---|---|
| T01 | | | | | |
| T02 | | | | | |
| T03 | | | | | |
| T04 | | | | | |
| T05 | | | | | |
| T06 | | | | | |
| T07 | | | | | |
| T08 | | | | | |
| T09 | | | | | |
| T10 | | | | | |
| T11 | | | | | |
| T12 | | | | | |

Preuves à archiver dans `artifacts/` (ignoré par git) : sorties `certutil -v -dump`,
sorties `openssl`, capture de la page d'erreur Edge avec le code, export du journal CA.

## 6. Critères de sortie

- T06 et T08 passent : la hiérarchie ECDSA est saine et Chromium l'accepte.
- T07 reproduit exactement le symptôme de production (OID 1.2.840.10045.4.3).
- T09 et T10 documentent la remédiation si la chaîne de production est touchée.

## 7. Transposition à la production

Sur chaque CA de production :

```
certutil -getreg ca\csp\AlternateSignatureAlgorithm
certutil -v -dump <certificat de CA> | findstr ObjectId
```

Si la valeur est 1 ou si un certificat de CA porte 1.2.840.10045.4.3, appliquer
T08 (feuilles seules) ou T10 (chaîne), après sauvegarde de la CA et des clés.

---

Rédigé et signé par **ukestr Analyst**, le 2026-09-18.
