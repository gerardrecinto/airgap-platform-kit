(function () {
  'use strict';
  var root = document.documentElement;

  // Copy buttons. Hidden in the markup so they only appear when JS can make them work.
  var status = document.getElementById('copy-status');
  function say(t) { if (status) status.textContent = t; }
  document.querySelectorAll('.copy').forEach(function (btn) {
    btn.hidden = false;
    btn.addEventListener('click', function () {
      var el = document.getElementById(btn.getAttribute('data-target'));
      if (!el) return;
      var text = el.innerText.trim();
      function reset() { btn.textContent = 'Copy'; btn.classList.remove('done'); }
      function done() {
        btn.textContent = 'Copied'; btn.classList.add('done'); say('Commands copied.');
        setTimeout(reset, 2000);
      }
      function fallback() {
        try {
          var r = document.createRange(); r.selectNodeContents(el);
          var s = window.getSelection(); s.removeAllRanges(); s.addRange(r);
        } catch (e) { /* selection is best effort */ }
        btn.textContent = 'Press Ctrl or Cmd C';
        say('Copy is not available here. The commands are selected, press Ctrl or Command C.');
        setTimeout(reset, 4000);
      }
      if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(text).then(done, fallback);
      else fallback();
    });
  });

  // Motion is gated by the head script: the js class is only set without reduced motion.
  if (!root.classList.contains('js')) return;

  var targets = document.querySelectorAll('main > section.panel, main > section.strip');
  var io = new IntersectionObserver(function (entries) {
    entries.forEach(function (e) {
      if (!e.isIntersecting) return;
      e.target.classList.add('in');
      io.unobserve(e.target);
    });
  }, { threshold: 0.06, rootMargin: '0px 0px -8% 0px' });
  targets.forEach(function (el) { el.classList.add('reveal'); io.observe(el); });

  // Cards and facts cascade instead of landing together.
  document.querySelectorAll('.cards .card, .facts > div').forEach(function (el, i) {
    el.style.setProperty('--d', ((i % 4) * 90) + 'ms');
  });

  var bar = document.querySelector('.progress');
  var ticking = false;
  function frame() {
    ticking = false;
    var max = document.documentElement.scrollHeight - window.innerHeight;
    if (bar && max > 0) bar.style.transform = 'scaleX(' + Math.min(1, window.scrollY / max) + ')';
  }
  window.addEventListener('scroll', function () {
    if (!ticking) { ticking = true; requestAnimationFrame(frame); }
  }, { passive: true });
  frame();
})();
