# Specification: Whisper Box — Transcripteur audio/vidéo local macOS

## Problem Statement
Transcrire un fichier audio ou vidéo manuellement est lent : upload sur un service cloud, attente, récupération du texte, répétition. Les solutions cloud posent des problèmes de confidentialité (données client, enregistrements internes) et de coût. OpenAI Whisper tourne localement et produit des transcriptions de haute qualité, mais son interface est en ligne de commande — inaccessible pour un non-développeur.

**Whisper Box** offre une interface graphique locale, macOS-native, qui permet de glisser-déposer un fichier, choisir ses options, lancer la transcription et récupérer le texte — sans quitter son bureau, sans cloud.

---

## Users and Personas

### Persona 1 — Consultant / Analyst
Roldy, consultant Odoo. Enregistre des réunions clients ou des formations. Veut une transcription rapide pour en faire un compte-rendu. N'a pas de terminal ouvert en permanence. Valeur clé : vitesse et simplicité.

### Persona 2 — Knowledge Worker
Utilisateur non-technique qui reçoit des fichiers audio (interviews, podcasts, notes vocales). Veut du texte exportable. Valeur clé : fiabilité et formats de sortie utilisables.

---

## Functional Requirements

### User Story 1 — Soumettre un fichier à la transcription
En tant qu'utilisateur, je veux sélectionner un fichier audio ou vidéo (via un bouton ou glisser-déposer) et lancer sa transcription, de façon à obtenir un texte sans ouvrir un terminal.

**Acceptance Criteria:**
- [ ] L'utilisateur peut cliquer sur une zone pour ouvrir un file picker macOS natif
- [ ] L'utilisateur peut glisser-déposer un fichier sur la zone de dépôt
- [ ] L'utilisateur peut coller ou saisir manuellement un chemin absolu vers un fichier
- [ ] Les formats supportés sont : mp3, mp4, wav, m4a, ogg, flac, webm, mkv, avi, mov, aac
- [ ] Un fichier non supporté affiche un message d'erreur explicite (liste des formats acceptés)
- [ ] Si ffmpeg n'est pas installé, un message d'erreur indique comment l'installer (`brew install ffmpeg`)
- [ ] Le fichier n'est pas copié — seul le chemin est stocké

### User Story 2 — Configurer la transcription
En tant qu'utilisateur, je veux choisir le modèle Whisper et la langue avant de lancer, de façon à optimiser vitesse/précision selon mon cas.

**Acceptance Criteria:**
- [ ] L'utilisateur peut sélectionner le modèle : tiny, base, small, medium, large (défaut : base)
- [ ] L'utilisateur peut sélectionner la langue : Détection automatique ou liste des langues principales (fr, en, nl, de, es, it, pt, ar, zh, ja)
- [ ] L'utilisateur peut choisir le format de sortie : txt, srt, vtt, json, tsv (défaut : txt)
- [ ] L'utilisateur peut choisir le dossier de destination de la transcription (défaut : `~/Whisper Memory/transcripts/`)
- [ ] Ces paramètres sont mémorisés comme valeurs par défaut pour la prochaine session

### User Story 3 — Suivre la progression en temps réel
En tant qu'utilisateur, je veux voir la progression de la transcription pendant qu'elle tourne, de façon à savoir quand elle sera terminée sans pollier constamment.

**Acceptance Criteria:**
- [ ] Une barre de progression s'affiche pendant la transcription (pourcentage ou segments traités)
- [ ] Les logs en temps réel sont affichés dans un panneau de log scrollable
- [ ] Le statut du job s'affiche clairement : En attente / En cours / Terminé / Erreur
- [ ] En cas d'erreur, le message d'erreur complet est affiché (pas juste "Erreur")
- [ ] L'utilisateur peut annuler une transcription en cours
- [ ] L'icône menu bar reflète l'état : idle (neutre) / running (spinner) / done (badge)

### User Story 4 — Récupérer le résultat
En tant qu'utilisateur, je veux accéder au texte transcrit et l'exporter, de façon à l'utiliser dans d'autres outils (Word, email, etc.).

**Acceptance Criteria:**
- [ ] Le texte transcrit s'affiche dans l'app dès que la transcription est terminée
- [ ] Un bouton "Ouvrir le fichier" ouvre le fichier de sortie dans l'éditeur par défaut macOS
- [ ] Un bouton "Copier tout" copie le texte dans le presse-papiers
- [ ] Un bouton "Révéler dans le Finder" ouvre le dossier contenant le fichier
- [ ] Le fichier de sortie est nommé `[nom_du_fichier_source]_[timestamp].[extension]`

### User Story 5 — Consulter l'historique
En tant qu'utilisateur, je veux voir toutes mes transcriptions passées, de façon à retrouver un texte sans devoir naviguer dans le Finder.

**Acceptance Criteria:**
- [ ] L'onglet Historique liste toutes les transcriptions passées (les plus récentes en premier)
- [ ] Chaque entrée affiche : nom du fichier source, modèle utilisé, langue, durée audio, durée de traitement, statut, date
- [ ] L'utilisateur peut filtrer par statut (succès / erreur)
- [ ] L'utilisateur peut rechercher par nom de fichier (recherche en temps réel)
- [ ] L'utilisateur peut ouvrir le fichier de sortie depuis l'historique
- [ ] L'utilisateur peut supprimer une entrée de l'historique (avec confirmation) — cela ne supprime PAS le fichier de sortie
- [ ] L'utilisateur peut relancer la même transcription (avec les mêmes paramètres) depuis l'historique

### User Story 6 — Consulter les logs d'exécution
En tant qu'utilisateur avancé, je veux accéder aux logs détaillés de chaque transcription, de façon à diagnostiquer les erreurs.

**Acceptance Criteria:**
- [ ] L'onglet Logs liste tous les logs d'exécution (résumés, sans contenu complet par défaut)
- [ ] Un clic sur un log affiche le contenu complet (stderr + stdout de Whisper)
- [ ] L'utilisateur peut filtrer par statut (running / success / error)
- [ ] L'utilisateur peut supprimer un log (avec confirmation)
- [ ] Les logs incluent : type d'opération, fichier source, modèle, durée, statut, timestamp

### User Story 7 — Gérer les paramètres
En tant qu'utilisateur, je veux personnaliser le comportement par défaut de l'app, de façon à ne pas reconfigurer à chaque transcription.

**Acceptance Criteria:**
- [ ] L'utilisateur peut définir le modèle Whisper par défaut
- [ ] L'utilisateur peut définir le format de sortie par défaut
- [ ] L'utilisateur peut définir le dossier de sortie par défaut
- [ ] L'utilisateur peut définir la langue par défaut (y compris "détection auto")
- [ ] Un bouton de diagnostic vérifie si ffmpeg est disponible dans le PATH et affiche sa version
- [ ] L'utilisateur peut voir le chemin du data directory (`~/Whisper Memory/`)
- [ ] L'utilisateur peut ouvrir le data directory dans le Finder

### User Story 8 — Accès rapide via la barre de menu
En tant qu'utilisateur, je veux accéder à Whisper Box depuis la barre de menu macOS (status bar), de façon à ne pas devoir chercher l'app dans le Dock ou les apps ouvertes.

**Acceptance Criteria:**
- [ ] Une icône Whisper Box apparaît dans la barre de menu macOS lors du lancement de l'app
- [ ] Un clic sur l'icône affiche un menu avec : Ouvrir / Afficher le statut / Quitter
- [ ] Le statut affiché indique si une transcription est en cours et son avancement
- [ ] L'option "Ouvrir" focus la fenêtre principale dans le navigateur (ou l'ouvre si elle est fermée)
- [ ] L'app peut être quittée via le menu bar sans passer par la fenêtre principale

---

## Non-Functional Requirements
- **Confidentialité** : aucune donnée audio, texte ou métadonnée n'est envoyée sur internet
- **Offline-first** : l'app fonctionne sans connexion réseau (hors premier téléchargement du modèle Whisper)
- **Modèles Whisper** : téléchargés dans `~/.cache/whisper/` (chemin par défaut de la lib) — l'app n'y touche pas
- **Compatibilité** : macOS 12.0 (Monterey) minimum, arm64 et x86_64
- **Langue UI** : Français par défaut, Anglais disponible (i18n comme OTB)

---

## Out of Scope (V1)
- Enregistrement live depuis le microphone
- Transcription batch (plusieurs fichiers en parallèle) — la queue traite les jobs séquentiellement
- Traduction du texte transcrit
- Édition du texte dans l'app
- Synchronisation/partage cloud
- Diarisation (qui parle quand)
- Windows / Linux packaging

---

## Review & Acceptance Checklist
- [x] Tous les user stories ont des acceptance criteria testables
- [x] Les cas limites sont documentés (fichier non supporté, ffmpeg absent, annulation)
- [x] Out-of-scope est explicite
- [x] Aucun détail d'implémentation technique dans la spec
- [x] Les flux de données sont clairs (fichier local → Whisper local → fichier texte local)
