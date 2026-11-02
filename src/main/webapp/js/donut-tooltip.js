// donut-tooltip.js - makes .donut-svg pie/donut charts interactive: hovering
// a segment highlights it (via CSS - see .donut-segment:hover in
// ir-ams-railway-ui.css) and shows a floating tooltip with that segment's
// label, count, and percentage (read from data-label/data-value/data-percent
// attributes already present on each <circle class="donut-segment">).
//
// Shared/generic on purpose: works for any number of .donut-svg charts on a
// page, each with any number of segments - a page just needs to render the
// SVG markup with the right data-* attributes and classes; this script does
// the rest, the same "one shared behavior, no page-specific JS" approach as
// session-timer.js.
(function () {
    'use strict';

    var charts = document.querySelectorAll('.donut-svg');
    if (!charts.length) {
        return;
    }

    charts.forEach(function (svg) {
        var wrap = svg.closest('.donut');
        if (!wrap) {
            return;
        }

        var tooltip = document.createElement('div');
        tooltip.className = 'donut-tooltip';
        tooltip.setAttribute('role', 'tooltip');
        tooltip.hidden = true;
        wrap.appendChild(tooltip);

        function showTooltip(segment, evt) {
            var label = segment.getAttribute('data-label') || '';
            var value = segment.getAttribute('data-value') || '';
            var percent = segment.getAttribute('data-percent');

            tooltip.innerHTML = '<strong></strong><span></span>';
            tooltip.querySelector('strong').textContent = label;
            tooltip.querySelector('span').textContent = percent != null
                ? value + ' (' + percent + '%)'
                : value;

            tooltip.hidden = false;
            positionTooltip(evt);
        }

        function positionTooltip(evt) {
            var wrapRect = wrap.getBoundingClientRect();
            // Position relative to the donut itself (not the page) so it
            // stays correctly placed regardless of scroll position.
            var x = evt.clientX - wrapRect.left;
            var y = evt.clientY - wrapRect.top;
            tooltip.style.left = x + 'px';
            tooltip.style.top = y + 'px';
        }

        function hideTooltip() {
            tooltip.hidden = true;
        }

        svg.querySelectorAll('.donut-segment').forEach(function (segment) {
            segment.addEventListener('mouseenter', function (evt) {
                segment.classList.add('donut-segment-active');
                showTooltip(segment, evt);
            });
            segment.addEventListener('mousemove', positionTooltip);
            segment.addEventListener('mouseleave', function () {
                segment.classList.remove('donut-segment-active');
                hideTooltip();
            });
            // Touch devices: tap to show, tap elsewhere to dismiss - mouseenter
            // never fires on touch, so without this the chart would be
            // silently non-interactive on mobile/tablet.
            segment.addEventListener('touchstart', function (evt) {
                svg.querySelectorAll('.donut-segment-active').forEach(function (el) {
                    el.classList.remove('donut-segment-active');
                });
                segment.classList.add('donut-segment-active');
                var touch = evt.touches[0];
                showTooltip(segment, { clientX: touch.clientX, clientY: touch.clientY });
            }, { passive: true });
        });

        document.addEventListener('touchstart', function (evt) {
            if (!wrap.contains(evt.target)) {
                svg.querySelectorAll('.donut-segment-active').forEach(function (el) {
                    el.classList.remove('donut-segment-active');
                });
                hideTooltip();
            }
        }, { passive: true });
    });
})();
