// ============================================================
// My Train — landing page interactivity
// Scroll-blurred nav, cursor-follow glass highlight, orb parallax,
// reveal-on-scroll, PNR + waitlist form handlers.
// All motion effects respect prefers-reduced-motion.
// ============================================================

(function () {
  "use strict";

  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // ---- Sticky nav: add .scrolled once the page moves ----
  const nav = document.getElementById("nav");
  const onScrollNav = () => {
    if (!nav) return;
    nav.classList.toggle("scrolled", window.scrollY > 12);
  };
  onScrollNav();
  window.addEventListener("scroll", onScrollNav, { passive: true });

  // ---- Cursor-follow specular highlight on interactive glass cards ----
  // Sets --mx / --my (percentages) consumed by .glass--interactive::after.
  if (!reduceMotion && window.matchMedia("(hover: hover)").matches) {
    const interactives = document.querySelectorAll(".glass--interactive");
    interactives.forEach((el) => {
      el.addEventListener("pointermove", (e) => {
        const r = el.getBoundingClientRect();
        const mx = ((e.clientX - r.left) / r.width) * 100;
        const my = ((e.clientY - r.top) / r.height) * 100;
        el.style.setProperty("--mx", mx + "%");
        el.style.setProperty("--my", my + "%");
      });
      el.addEventListener("pointerleave", () => {
        el.style.setProperty("--mx", "50%");
        el.style.setProperty("--my", "-20%");
      });
    });
  }

  // ---- Subtle device tilt following the pointer ----
  const device = document.querySelector("[data-tilt] .phone");
  if (device && !reduceMotion && window.matchMedia("(hover: hover)").matches) {
    const wrap = device.closest("[data-tilt]");
    wrap.addEventListener("pointermove", (e) => {
      const r = wrap.getBoundingClientRect();
      const rx = ((e.clientY - r.top) / r.height - 0.5) * -6;
      const ry = ((e.clientX - r.left) / r.width - 0.5) * 8;
      device.style.transform = `perspective(1000px) rotateX(${rx}deg) rotateY(${ry}deg)`;
    });
    wrap.addEventListener("pointerleave", () => {
      device.style.transform = "perspective(1000px) rotateX(0) rotateY(0)";
    });
  }

  // ---- Orb parallax on scroll (background color refraction shift) ----
  const orbs = Array.from(document.querySelectorAll(".orb"));
  if (orbs.length && !reduceMotion) {
    let ticking = false;
    const applyParallax = () => {
      const y = window.scrollY;
      orbs.forEach((orb) => {
        const depth = parseFloat(orb.getAttribute("data-parallax")) || 0.1;
        orb.style.transform = `translate3d(0, ${y * depth}px, 0)`;
      });
      ticking = false;
    };
    window.addEventListener(
      "scroll",
      () => {
        if (!ticking) {
          window.requestAnimationFrame(applyParallax);
          ticking = true;
        }
      },
      { passive: true }
    );
  }

  // ---- Reveal-on-scroll ----
  const revealEls = document.querySelectorAll(".reveal");
  if (reduceMotion || !("IntersectionObserver" in window)) {
    revealEls.forEach((el) => el.classList.add("is-visible"));
  } else {
    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-visible");
            io.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.12, rootMargin: "0px 0px -8% 0px" }
    );
    revealEls.forEach((el) => io.observe(el));
  }

  // ---- PNR demo form: numeric only, gentle validation feedback ----
  const pnrForm = document.getElementById("pnrForm");
  const pnrInput = document.getElementById("pnrInput");
  if (pnrForm && pnrInput) {
    pnrInput.addEventListener("input", () => {
      pnrInput.value = pnrInput.value.replace(/\D/g, "").slice(0, 10);
    });
    pnrForm.addEventListener("submit", (e) => {
      e.preventDefault();
      const valid = pnrInput.value.length === 10;
      pnrInput.style.borderColor = valid ? "" : "var(--red)";
      if (valid) {
        // Marketing demo: no backend. Nudge users toward the real thing.
        pnrInput.blur();
      } else {
        pnrInput.focus();
      }
    });
  }

  // ---- Waitlist form: client-side confirmation (no backend wired yet) ----
  const waitlistForm = document.getElementById("waitlistForm");
  const waitlistEmail = document.getElementById("waitlistEmail");
  const waitlistNote = document.getElementById("waitlistNote");
  if (waitlistForm && waitlistEmail && waitlistNote) {
    waitlistForm.addEventListener("submit", (e) => {
      e.preventDefault();
      const value = waitlistEmail.value.trim();
      const ok = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
      if (!ok) {
        waitlistEmail.style.borderColor = "var(--red)";
        waitlistEmail.focus();
        return;
      }
      waitlistEmail.style.borderColor = "";
      waitlistEmail.value = "";
      waitlistEmail.disabled = true;
      waitlistNote.textContent = "You're on the list — we'll be in touch at launch.";
      waitlistNote.classList.add("is-success");
    });
  }
})();
