# 🔎 Chercheur de VM Oracle gratuite — version cloud (GitHub Actions)

Fait tourner la recherche d'une instance Oracle « Always Free » (ARM) **24/7 sur l'infra
GitHub**, ton PC peut être éteint. Toutes les ~10 min, GitHub tente de créer la VM
(2 OCPU/12 Go puis 1 OCPU/6 Go). Au succès → **notification iPhone (ntfy) + email**, l'IP est
enregistrée dans `FOUND.flag`, et les passes suivantes s'arrêtent toutes seules.

> 💰 **Coût : 0 €** si le dépôt est **public** (minutes GitHub Actions illimitées). Tes secrets
> restent chiffrés et privés même sur un dépôt public.

---

## Étapes (≈ 10 min, une seule fois)

### 1) Créer le dépôt GitHub
1. https://github.com/new
2. Nom : `oracle-vm-finder` · Visibilité : **Public** · → **Create repository**.

### 2) Pousser ces fichiers
Dans un terminal, depuis le dossier `C:\Users\YASSINE DAOUD\oracle-vm-finder` :
```bash
cd ~/oracle-vm-finder
git init -b main
git add .
git commit -m "Chercheur VM Oracle (GitHub Actions)"
git remote add origin https://github.com/<TON_PSEUDO>/oracle-vm-finder.git
git push -u origin main
```

### 3) Ajouter les secrets
Sur le dépôt → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**.
Crée **chacun** de ces secrets (nom = valeur) :

| Nom du secret | Valeur |
|---|---|
| `OCI_USER` | `ocid1.user.oc1..aaaaaaaa4tgchnbf3cvbeyrswbqrrpgycbyvl3ztumn4hm6f56anrbyfdxvq` |
| `OCI_FINGERPRINT` | `1d:04:cb:86:a3:ca:f5:cb:db:5f:c7:63:06:4c:58:3f` |
| `OCI_TENANCY` | `ocid1.tenancy.oc1..aaaaaaaakwisshatffa7oy324vwtkvwruaig2qqxf6nqyqo5ra7ethsdjwda` |
| `OCI_COMPARTMENT` | `ocid1.tenancy.oc1..aaaaaaaakwisshatffa7oy324vwtkvwruaig2qqxf6nqyqo5ra7ethsdjwda` |
| `OCI_REGION` | `eu-marseille-1` |
| `OCI_SUBNET` | `ocid1.subnet.oc1.eu-marseille-1.aaaaaaaa7zbnjpegk53npl3or3o46mdi73r2gqe2wea66vzexqr7ihl4ptya` |
| `SSH_PUBLIC_KEY` | `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEnrV5gfstjmDBcz7rSAv1HxS3bCrzD2spO/8lSyMUgb trainova-oracle` |
| `NTFY_TOPIC` | `trainova-yassine-2026` |
| `NTFY_EMAIL` | **ton adresse email** (où recevoir l'alerte) |
| `OCI_KEY_PEM` | **le contenu** du fichier `C:\Users\YASSINE DAOUD\.oci\oci_api_key.pem` (voir ci-dessous) |

**Pour `OCI_KEY_PEM`** : ouvre le fichier `oci_api_key.pem` dans le Bloc-notes, **sélectionne tout**
(Ctrl+A), copie (Ctrl+C), et colle dans la valeur du secret — **y compris** les lignes
`-----BEGIN PRIVATE KEY-----` et `-----END PRIVATE KEY-----`.

### 4) Tester tout de suite (sans attendre le cron)
Onglet **Actions** → workflow **Find Oracle Free VM** → bouton **Run workflow** → **Run workflow**.
Ouvre l'exécution pour voir les logs en direct. Si tu vois `✗ … indisponible (capacité)`, c'est
**normal** (l'ARM gratuit est saturé) : le cron continuera d'essayer toutes les 10 min.

---

## Quand la VM est obtenue
- 📱📧 Tu reçois **« 🟢 ORACLE VM ▸ IP PRÊTE »** sur l'iPhone et par email, avec l'**IP publique**.
- Le fichier `FOUND.flag` (dans le dépôt) contient l'IP + l'OCID.
- Les passes suivantes s'arrêtent automatiquement (drapeau détecté).
- Ensuite : mettre cette IP dans `~/.ssh/config` (bloc `trainova-oracle`) puis lancer
  `deploy/oracle/bootstrap-oracle.sh` côté projet Trainova.

## Pour tout relancer plus tard (nouvelle VM)
Supprime `FOUND.flag` du dépôt (Delete file → Commit) : le cron repart.

## Pour arrêter complètement
Onglet **Actions** → **Find Oracle Free VM** → menu **⋯** → **Disable workflow**.

---

## 🔐 Conseil sécurité (optionnel mais recommandé)
La clé API mise en secret est celle de ton compte Oracle. Pour limiter les risques en cas de fuite,
crée dans la console Oracle un **utilisateur dédié** (ex. `ci-vm-finder`) avec une **policy**
n'autorisant que la création d'instances dans le compartiment, génère **sa** clé API, et utilise
ces valeurs (`OCI_USER`, `OCI_FINGERPRINT`, `OCI_KEY_PEM`) à la place. Demande-moi si tu veux les
étapes détaillées.
