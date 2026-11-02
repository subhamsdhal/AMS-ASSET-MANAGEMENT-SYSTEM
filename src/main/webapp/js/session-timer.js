// session-timer.js - drives the topbar's "time remaining before automatic
// sign-out" pill (#sessionTimerPill / #sessionTimerText).
//
// Fault 1 (original): the very first version kept its countdown purely in
// a local JS variable, freshly reset to the FULL configured timeout on
// every single page load. Broke down the moment more than one tab of the
// app was open: each tab's countdown was seeded from ITS OWN load time, so
// switching between tabs showed a different, inconsistent number in each,
// and a tab left untouched while the user worked in another tab would
// still count its own local timer down to zero and force a real logout
// even though the shared server-side session was kept alive by the other
// tab.
//
// Fault 2 (the fix for Fault 1 above introduced this - reported twice by
// the user as "the timer still resets to 30 whenever I switch modules or
// click a function/button"): the cross-tab fix stored the deadline in
// localStorage, but *every single page load unconditionally overwrote it*
// with a fresh "now + totalSeconds", and the read side only ever trusted
// whichever deadline was LATER. A full page load's fresh deadline is
// always later than whatever the running countdown had ticked down to, so
// in practice this meant *every* navigation - switching modules, clicking
// into any function/button page - re-armed the full 30:00, exactly the
// "it keeps refreshing" complaint. Technically defensible (a real
// navigation IS a request, and Tomcat's own session timeout genuinely does
// slide forward on every request) but not what was asked for, and not
// obviously correct UX either.
//
// Fix: the countdown is now anchored to a single deadline per LOGIN, set
// once on that session's first page load and never overwritten by later
// navigation - only read and continued. Switching modules or opening a
// function/button page picks up the SAME still-ticking deadline instead of
// re-arming it.
//
// Keyed by a `data-session-marker` value the pill carries (set from a
// `client_session_marker` session attribute LoginServlet mints fresh on
// every real sign-in) - NOT the actual JSESSIONID cookie. JSESSIONID is
// (correctly) HttpOnly, so client JS can never read it; the marker is a
// separate, non-sensitive random value that authenticates nothing and
// exists purely so this countdown can tell one login apart from another.
// A brand new login always gets a brand new marker, so a fresh countdown
// starts automatically exactly when it should - a real new sign-in - and
// never bleeds over from a previous login/logout on the same browser.
// Cross-tab sync is preserved because every tab opened during the same
// login renders the same marker and therefore uses the same storage key.
//
// Fix (in-page activity, unchanged from before): a genuine same-origin
// fetch()/XHR request the page makes WITHOUT navigating (e.g. AI Copilot's
// chat calls, Settings' save calls) also extends the real server-side
// session, so it's still treated as legitimate activity that pushes the
// deadline forward - unlike plain navigation, this can't be inferred from
// a page load alone, so window.fetch / XMLHttpRequest.prototype.send are
// wrapped once, globally, to catch it regardless of which script issues
// the request.
(function () {
    'use strict';

    var pill = document.getElementById('sessionTimerPill');
    var text = document.getElementById('sessionTimerText');
    if (!pill || !text) {
        return;
    }

    var totalSeconds = parseInt(pill.getAttribute('data-total-seconds'), 10);
    if (!totalSeconds || totalSeconds <= 0) {
        totalSeconds = 30 * 60;
    }

    var contextPath = pill.getAttribute('data-context-path') || '';

    // Scoped to exactly one login via the pill's data-session-marker (see
    // file header comment - this is NOT the JSESSIONID cookie, which is
    // HttpOnly and unreadable to JS by design). Falls back to a fixed
    // string only if a page somehow renders the pill without the
    // attribute (shouldn't happen post-deploy; keeps the countdown working
    // rather than breaking it either way).
    var sessionMarker = pill.getAttribute('data-session-marker') || 'unknown-session';
    var STORAGE_PREFIX = 'amsSessionDeadlineAt:';
    var STORAGE_KEY = STORAGE_PREFIX + sessionMarker;

    function writeSharedDeadline(deadline) {
        try {
            window.localStorage.setItem(STORAGE_KEY, String(deadline));
        } catch (e) {
            // Ignore - see resolveDeadline().
        }
    }

    // Drops any deadline keys from a previous login on this browser (plus
    // the single old flat "amsSessionDeadlineAt" key an earlier, buggy
    // version of this file used) so localStorage doesn't accumulate one
    // stale entry per past session forever. Safe to run any time - it only
    // ever removes keys for a DIFFERENT login than the one this page is
    // using right now.
    function cleanupOtherSessionKeys() {
        try {
            window.localStorage.removeItem('amsSessionDeadlineAt');
            for (var i = window.localStorage.length - 1; i >= 0; i--) {
                var key = window.localStorage.key(i);
                if (key && key.indexOf(STORAGE_PREFIX) === 0 && key !== STORAGE_KEY) {
                    window.localStorage.removeItem(key);
                }
            }
        } catch (e) {
            // Non-fatal housekeeping - ignore.
        }
    }

    // The single source of truth for "when does this login's countdown
    // reach zero". Resolved ONCE per page load (not re-derived every
    // tick): if a still-valid deadline already exists for this exact
    // session, every page load - including full navigations between
    // modules and function/button pages - just continues counting it down
    // instead of re-arming it. A fresh deadline is only minted when none
    // exists yet (this session's very first page load) or the stored one
    // has already passed.
    var deadline;
    try {
        var stored = window.localStorage.getItem(STORAGE_KEY);
        var storedDeadline = stored ? parseInt(stored, 10) : NaN;
        if (!isNaN(storedDeadline) && storedDeadline > Date.now()) {
            deadline = storedDeadline;
        }
    } catch (e) {
        // localStorage unavailable (private browsing lockdown, etc.) - fall
        // through to minting a fresh deadline below, matching single-tab
        // behavior rather than failing the countdown.
    }
    if (!deadline) {
        deadline = Date.now() + (totalSeconds * 1000);
        writeSharedDeadline(deadline);
        cleanupOtherSessionKeys();
    }

    function readSharedDeadline() {
        // Cross-tab sync: a sibling tab's genuine AJAX activity
        // (refreshDeadline() below) writes a later deadline under this
        // same session key, so re-reading from storage every tick (rather
        // than trusting the in-memory `deadline` forever) lets this tab's
        // display follow that extension too.
        try {
            var stored = window.localStorage.getItem(STORAGE_KEY);
            var storedDeadline = stored ? parseInt(stored, 10) : NaN;
            if (!isNaN(storedDeadline) && storedDeadline > deadline) {
                deadline = storedDeadline;
            }
        } catch (e) {
            // Ignore - keep using the last known in-memory deadline.
        }
        return deadline;
    }

    function isSameOriginUrl(url) {
        try {
            return new URL(url, window.location.href).origin === window.location.origin;
        } catch (e) {
            // Relative URLs ("CopilotServlet", "/Foo") resolve fine above;
            // anything that still throws isn't a normal request URL - treat
            // as not-same-origin rather than risk a false positive.
            return false;
        }
    }

    function refreshDeadline() {
        // Genuine in-page activity (unlike plain navigation) DOES extend
        // the deadline - see the file header comment for why these two
        // cases are treated differently.
        deadline = Date.now() + (totalSeconds * 1000);
        writeSharedDeadline(deadline);
    }

    if (typeof window.fetch === 'function') {
        var originalFetch = window.fetch;
        window.fetch = function (input, init) {
            var url = typeof input === 'string' ? input : (input && input.url);
            if (url && isSameOriginUrl(url)) {
                refreshDeadline();
            }
            return originalFetch.apply(this, arguments);
        };
    }

    if (typeof window.XMLHttpRequest === 'function') {
        var originalOpen = window.XMLHttpRequest.prototype.open;
        window.XMLHttpRequest.prototype.open = function (method, url) {
            if (url && isSameOriginUrl(url)) {
                this.__amsSessionRelevant = true;
            }
            return originalOpen.apply(this, arguments);
        };

        var originalSend = window.XMLHttpRequest.prototype.send;
        window.XMLHttpRequest.prototype.send = function () {
            if (this.__amsSessionRelevant) {
                refreshDeadline();
            }
            return originalSend.apply(this, arguments);
        };
    }

    function render(remainingSeconds) {
        var clamped = Math.max(0, remainingSeconds);
        var minutes = Math.floor(clamped / 60);
        var seconds = clamped % 60;
        text.textContent = String(minutes).padStart(2, '0') + ':' + String(seconds).padStart(2, '0');

        pill.classList.remove('session-timer-warning', 'session-timer-critical');
        if (clamped <= 60) {
            pill.classList.add('session-timer-critical');
        } else if (clamped <= 300) {
            pill.classList.add('session-timer-warning');
        }
    }

    render(Math.round((readSharedDeadline() - Date.now()) / 1000));

    var tick = setInterval(function () {
        var deadline = readSharedDeadline();
        var remaining = Math.round((deadline - Date.now()) / 1000);

        if (remaining <= 0) {
            clearInterval(tick);
            text.textContent = '00:00';
            // Real, forced sign-out - not just a display. By the time this
            // fires, the freshest deadline known across every open tab has
            // passed, so the server-side session is genuinely at (or past)
            // expiry regardless of which tab is active.
            window.location.href = contextPath + '/logout.jsp?reason=timeout';
            return;
        }

        render(remaining);
    }, 1000);
})();
