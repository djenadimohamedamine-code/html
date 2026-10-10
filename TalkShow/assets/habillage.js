/* ==========================================================================
   TalkShow — POP TV / moteur d'habillage (Master Invite V1)

   PRODUCTION (template_invite.html) :
     - aucun autoplay
     - aucune barre Preview (même pas dans le DOM)
     - aucun raccourci clavier
     - canvas transparent
     - window.playSequence = playSequence  (déclenchement externe)

   PREVIEW (template_invite.html?preview=1) :
     - barre PLAY créée dynamiquement
     - bouton PLAY, touche Space, touche P
     - statut STANDBY / ON AIR

   Timeline : 0 ms → fade-in (400 ms, opacity seule) → affichage
              5000 ms → suppression immédiate de .playing → Standby
              aucune animation de sortie.
   ========================================================================== */

(function () {
    'use strict';

    var HOLD_MS = 5000;
    var timer = null;
    var statusEl = null;

    function setStatus(onAir) {
        if (!statusEl) return;
        statusEl.textContent = onAir ? 'ON AIR' : 'STANDBY';
        statusEl.setAttribute('data-onair', onAir ? '1' : '0');
    }

    function playSequence() {
        var body = document.body;
        if (!body) return;

        if (timer) {
            clearTimeout(timer);
            timer = null;
        }

        /* relance depuis 0 ms : retrait + reflow + ré-ajout de .playing */
        body.classList.remove('playing');
        void body.offsetWidth;
        body.classList.add('playing');
        setStatus(true);

        timer = setTimeout(function () {
            body.classList.remove('playing');   /* hard cut, pas de sortie */
            setStatus(false);
            timer = null;
        }, HOLD_MS);
    }

    /* déclenchement externe (console / système de contrôle broadcast) */
    window.playSequence = playSequence;

    /* ---- Barre Preview : construite UNIQUEMENT si ?preview=1 -------------- */
    function buildPreviewBar() {
        var bar = document.createElement('div');
        bar.className = 'ts-bar';

        var btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'ts-play';
        btn.textContent = '▶ PLAY';

        var st = document.createElement('span');
        st.className = 'ts-status';
        st.textContent = 'STANDBY';
        st.setAttribute('data-onair', '0');

        bar.appendChild(btn);
        bar.appendChild(st);
        document.body.appendChild(bar);
        statusEl = st;

        btn.addEventListener('click', function () {
            playSequence();
        });

        document.addEventListener('keydown', function (e) {
            var k = String(e.key || '').toLowerCase();
            if (e.code === 'Space' || k === ' ' || k === 'spacebar' || k === 'p') {
                e.preventDefault();
                playSequence();
            }
        });

        setStatus(false);   /* état initial : STANDBY */
    }

    /* ---- Calque de balayage lumineux du nom -------------------------------
       .ts-name::after duplique le texte via content: attr(data-text) :
       meme source = texte strictement identique (meme police, taille, poids,
       letter-spacing, line-height, position). Sans attribut, le pseudo-element
       est vide -> aucune lumiere (degradation sure, texte principal intact). */
    function tagSweepTexts() {
        var nodes = document.querySelectorAll('.ts-name');
        for (var i = 0; i < nodes.length; i++) {
            nodes[i].setAttribute('data-text', nodes[i].textContent);
        }
    }

    function init() {
        var preview = false;
        try {
            preview = new URLSearchParams(window.location.search).get('preview') === '1';
        } catch (e) {
            preview = false;
        }

        tagSweepTexts();

        if (preview) {
            buildPreviewBar();
        }
        /* PRODUCTION : rien d'autre — pas d'autoplay, pas de barre, pas de raccourci */
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
