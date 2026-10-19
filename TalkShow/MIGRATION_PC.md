# MIGRATION PC — Projet TalkShow
> Créé le 2026-10-16 — Document de passation avant changement de PC

---

## Informations générales

| Clé | Valeur |
|-----|--------|
| **Nom du projet** | TalkShow Broadcast Habillage |
| **Chemin sur l'ancien PC** | `F:\spark\TalkShow` |
| **Repository GitHub** | https://github.com/djenadimohamedamine-code/html |
| **Branche principale** | `main` |
| **Branche de sauvegarde migration** | `backup/talkshow-pc-migration-2026-10-16` |
| **Compte GitHub** | djenadimohamedamine-code |

---

## Architecture principale

```
F:\spark\TalkShow\
├── TALKSHOW.html                   ← Interface web principale (panneau de contrôle)
├── render_talkshow.py              ← Renderer Python (Playwright + FFmpeg broadcast)
├── PANNEAU_DE_CONTROLE\
│   ├── INTERFACE_WEB.bat           ← Lanceur du serveur local
│   ├── queue.json                  ← État dynamique (ignoré par Git)
│   └── current_state.json          ← État courant (ignoré par Git)
├── assets\
│   ├── fonts\                      ← Toutes les polices (Arabic, Latin, etc.)
│   ├── talkshow.css                ← CSS principal / familles 1 & 2
│   ├── habillage.js                ← Logique JS partagée
│   ├── synthe1.css                 ← Synthé 1 (famille 1)
│   ├── synthe2.css                 ← Synthé 2 (famille 2)
│   ├── synthe3.css                 ← Synthé 3 (famille V3 — GLASS TRANSPARENT)
│   ├── titre3.css                  ← Titre 3 (famille V3 — GLASS TRANSPARENT)
│   ├── headline2.css               ← Headline 2
│   └── bug_v2.css                  ← Bug (famille bug)
├── template_titre.html             ← Template Titre 1
├── template_synthe1.html           ← Template Synthé 1
├── template_titre2.html            ← Template Titre 2
├── template_synthe2.html           ← Template Synthé 2
├── template_titre3.html            ← Template Titre 3 (V3 Glass)
├── template_synthe3.html           ← Template Synthé 3 (V3 Glass — WAAPI animation)
├── template_generique.html         ← Template Générique
├── template_bug.html               ← Template Bug
├── EXPORTS\                        ← Fichiers MOV/MP4 finaux (non versionnés — voir Git LFS)
└── PREVIEW\                        ← Aperçus MP4 (non versionnés)
```

---

## Comment lancer le projet

### 1. Démarrer le serveur local

Double-cliquer sur :
```
PANNEAU_DE_CONTROLE\INTERFACE_WEB.bat
```
Cela démarre un serveur Python sur **http://127.0.0.1:8730/**

### 2. Ouvrir le panneau de contrôle
Dans un navigateur (Chrome recommandé) :
```
http://127.0.0.1:8730/TALKSHOW.html
```

### 3. Générer un export broadcast MOV
Depuis un terminal dans `F:\spark\TalkShow` :
```bash
python render_talkshow.py
```
Le renderer Playwright capture les frames à 50 fps puis FFmpeg génère le `.mov` final.

---

## Configuration broadcast (VALIDÉE)

| Paramètre | Valeur |
|-----------|--------|
| **Résolution** | 1920×1080 |
| **Format conteneur** | QuickTime (.mov) |
| **Codec** | QTRLE (QuickTime Animation) |
| **pix_fmt** | argb (alpha inclus) |
| **Frame rate** | 25 fps (conteneur) |
| **Champs** | 50 champs/s — TFF (Top Field First) |
| **Durée** | 5 secondes = 125 frames vidéo |
| **Pipeline** | 250 PNG @50fps → tinterlace=interleave_top → MOV 25fps TFF |
| **Destination** | TriCaster 8000 |
| **field_order ffprobe** | `tb` (normal pour QTRLE — IDET confirme TFF) |

---

## Familles graphiques

### ✅ Famille V3 (Glass Transparent) — VALIDÉE
- **Synthé 3** (`template_synthe3.html` + `assets/synthe3.css`)
  - Full Width : `left: 120px; bottom: 120px; width: 1680px`
  - Nom : Noto Kufi Arabic, 700, 78px
  - Fonction : IBM Plex Arabic, 600, 50px
  - Animation : WAAPI horizontale (slide-in sobre)
  - Fond : `linear-gradient(180deg, rgba(8,10,13,0.12), rgba(8,10,13,0.055), rgba(8,10,13,0.14))`
  - Bordures : blanc 0.72 (top) / 0.28 (bottom) / 0.16 (sides)
  - Ombre légère, séparateur 1px blanc

- **Titre 3** (`template_titre3.html` + `assets/titre3.css`)
  - Même langage visuel que Synthé 3
  - Validé visuellement

### ✅ Famille 1
- Titre 1 (`template_titre.html`)
- Synthé 1 (`template_synthe1.html` + `assets/synthe1.css`)

### ✅ Famille 2
- Titre 2 (`template_titre2.html`)
- Synthé 2 (`template_synthe2.html` + `assets/synthe2.css`)

### ✅ Générique
- `template_generique.html`

### ✅ Bug
- `template_bug.html` + `assets/bug_v2.css`

---

## Fichiers MOV exportés (sur ancien PC uniquement — non versionnés)

> Ces fichiers sont dans `EXPORTS\` qui est ignoré par Git.
> Ils sont trop lourds pour GitHub classique.
> **Copie-les manuellement sur un disque externe avant de changer de PC.**

| Fichier | Taille | Description |
|---------|--------|-------------|
| `TalkShow_Synthe1_20261006_194231.mov` | 6.3 MB | Synthé 1 broadcast |
| `TalkShow_Synthe2_20261006_201224.mov` | 4.1 MB | Synthé 2 broadcast |
| `TalkShow_Synthe3_20261009_053834.mov` | 8.6 MB | Synthé 3 — version la plus récente |
| `TalkShow_Synthe3_20261009_060701.mov` | 8.6 MB | Synthé 3 — copie confirmée |
| `TalkShow_Titre1_20261006_195443.mov` | 9.6 MB | Titre 1 broadcast |
| `TalkShow_Titre2_20261006_202054.mov` | 6.0 MB | Titre 2 broadcast |
| `TalkShow_Titre3_20261009_065040.mov` | 13.1 MB | Titre 3 broadcast |
| `TVTC_V2_ALGER_REALTIME_30S_1080i50_UNCOMPRESSED.mov` | **~3 GB** | ⚠️ Fichier source non compressé — disque externe OBLIGATOIRE |

---

## Dépendances à installer sur le nouveau PC

### Python
```bash
pip install playwright
playwright install chromium
```

### FFmpeg
Installer FFmpeg et ffprobe puis ajouter leur dossier au PATH.
Le code appelle `ffmpeg` par son nom ; aucun chemin F: n'est imposé.
Vérifier avec `ffmpeg -version` et `ffprobe -version`.

Playwright Python fournit son runtime Node : aucune installation Node séparée
n'est nécessaire pour ce renderer.

---

## Commandes pour reprendre sur le nouveau PC

```bash
# 1. Cloner le dépôt
git clone https://github.com/djenadimohamedamine-code/html.git TalkShow

# 2. Aller dans le dossier
cd TalkShow

# 3. Récupérer toutes les branches
git fetch --all

# 4. Reprendre la sauvegarde dans une branche dédiée
git switch -c work/talkshow-migration origin/backup/talkshow-pc-migration-2026-10-16

# 5. Entrer dans le sous-dossier de l'application
cd TalkShow

# 6. Installer les dépendances
python -m pip install playwright
python -m playwright install chromium

# 7. Lancer le backend et ouvrir le panneau
python render_talkshow.py --serve
# Ne pas utiliser python -m http.server : il ne fournit pas les API de rendu.
```

---

## État au moment de la migration (2026-10-16)

### ✅ Sauvegardé sur la branche de migration

`main` ne contient pas tous les ajouts de cette sauvegarde.
- Tous les templates HTML (Titre, Synthé 1, 2, 3, Titre 3, Générique, Bug)
- Tous les CSS (synthe3.css, titre3.css glass transparent validé)
- habillage.js, talkshow.css
- Toutes les polices (fonts/)
- render_talkshow.py (pipeline QTRLE broadcast)
- TALKSHOW.html (panneau de contrôle)
- PANNEAU_DE_CONTROLE/INTERFACE_WEB.bat

### ⚠️ À sauvegarder manuellement sur disque externe
- `EXPORTS\TVTC_V2_ALGER_REALTIME_30S_1080i50_UNCOMPRESSED.mov` (~3 GB)
- `EXPORTS\TalkShow_*.mov` (les MOV broadcast validés)
- Tout le contenu de `PREVIEW\`

### ℹ️ Ce qui reste à faire (optionnel)
- Tester le rendu Synthé 3 avec le nouveau CSS glass sur le nouveau PC
- Vérifier le pipeline broadcast IDET sur le nouveau PC
- Régénérer les MOV si besoin (les sources sont complètes)

---

*Document généré automatiquement lors de la migration — 2026-10-16*

