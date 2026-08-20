/* OpenPocketCine landing - scroll choreography, cursor light-check, button physics.
  Depends on GSAP + ScrollTrigger (loaded via CDN in index.html).
  Everything degrades: no GSAP or prefers-reduced-motion means static content. */

(function () {
  "use strict";

  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const finePointer = window.matchMedia("(hover: hover) and (pointer: fine)").matches;
  const nativeMobileScroll = !finePointer || window.matchMedia("(max-width: 820px)").matches;
  const hasGsap = !!(window.gsap && window.ScrollTrigger);
  if (hasGsap) {
    gsap.registerPlugin(ScrollTrigger);
    // Mobile browser chrome changes the visual viewport during a fling. Do not
    // rebuild scroll-linked geometry in the middle of native momentum scrolling.
    ScrollTrigger.config({ ignoreMobileResize: true });
  }

  // Restoring scroll into a pinned section fights ScrollTrigger's layout
  // pass; a landing page can simply start at the top on reload.
  if ("scrollRestoration" in history) history.scrollRestoration = "manual";

  // ---- Anchor links: smooth-scroll in JS (CSS smooth fights pinning) ----
  function initAnchors() {
    document.addEventListener("click", (e) => {
      const link = e.target.closest('a[href^="#"]');
      if (!link) return;
      const target = document.querySelector(link.getAttribute("href"));
      if (!target) return;
      e.preventDefault();
      target.scrollIntoView({ behavior: reduceMotion ? "auto" : "smooth" });
    });
  }

  // ---- Nav: solid bar after scroll, tinted to the band under it ----
  function initNavMorph() {
    const nav = document.getElementById("nav");
    if (!nav) return;
    const bands = Array.from(document.querySelectorAll("[data-band]"));
    const apply = () => {
      nav.classList.toggle("scrolled", window.scrollY > 16);
      let theme = "dark";
      const y = 56;
      for (const band of bands) {
        const r = band.getBoundingClientRect();
        if (r.top <= y && r.bottom > y) {
          theme = band.dataset.band || "dark";
          break;
        }
      }
      nav.classList.toggle("nav--light", theme === "light");
      nav.classList.toggle("nav--dark", theme !== "light");
    };
    apply();
    window.addEventListener("scroll", apply, { passive: true });
  }

  // ---- Cursor light-check: gold spot + glass-card sheen follow the pointer ----
  // One rAF-throttled pointermove drives both: the fixed .spotlight layer reads
  // --mx/--my from the root; each .feat card reads --cx/--cy in its own space.
  function initSpotlight() {
    if (reduceMotion || !finePointer) return;
    const root = document.documentElement;
    const cards = document.querySelectorAll(".feat");
    let mx = 0, my = 0, ticking = false;
    const update = () => {
      root.style.setProperty("--mx", mx + "px");
      root.style.setProperty("--my", my + "px");
      cards.forEach((card) => {
        const r = card.getBoundingClientRect();
        card.style.setProperty("--cx", (mx - r.left) + "px");
        card.style.setProperty("--cy", (my - r.top) + "px");
      });
      ticking = false;
    };
    window.addEventListener("pointermove", (e) => {
      mx = e.clientX; my = e.clientY;
      document.body.classList.add("has-pointer");
      if (!ticking) {
        window.requestAnimationFrame(update);
        ticking = true;
      }
    }, { passive: true });
  }

  // ---- Magnetic buttons: pills lean toward the cursor, spring back on leave ----
  function initMagnetic() {
    if (reduceMotion || !finePointer) return;
    document.querySelectorAll(".btn--magnetic").forEach((btn) => {
      const strength = 0.22, limit = 9;
      btn.addEventListener("pointermove", (e) => {
        const r = btn.getBoundingClientRect();
        const dx = e.clientX - (r.left + r.width / 2);
        const dy = e.clientY - (r.top + r.height / 2);
        const clamp = (v) => Math.max(-limit, Math.min(limit, v * strength));
        btn.style.setProperty("--tx", clamp(dx) + "px");
        btn.style.setProperty("--ty", clamp(dy) + "px");
      });
      btn.addEventListener("pointerleave", () => {
        btn.style.setProperty("--tx", "0px");
        btn.style.setProperty("--ty", "0px");
      });
    });
  }

  // ---- Hero: entrance choreography + backdrop parallax + pointer tilt ----
  function initHero() {
    const backdrop = document.querySelector(".hero__backdrop img");
    const mock = document.querySelector(".hero__mock");

    if (hasGsap && !reduceMotion) {
      // Entrance: label, headline, lead, CTAs, then the monitor rises.
      gsap.from("[data-intro]", {
        opacity: 0,
        y: 26,
        duration: 0.9,
        ease: "power3.out",
        stagger: 0.09,
        clearProps: "opacity,transform",
      });
      // The set photo settles from a slight push-in as the page loads...
      if (backdrop) {
        gsap.from(backdrop, { scale: 1.08, duration: 1.6, ease: "power2.out" });
        // ...then drifts slower than the page on scroll (parallax).
        if (!nativeMobileScroll) {
          gsap.to(backdrop, {
            yPercent: 14,
            ease: "none",
            scrollTrigger: { trigger: ".hero", start: "top top", end: "bottom top", scrub: true },
          });
        }
      }
      // The monitor render drifts up slightly as you begin to scroll.
      if (mock && !nativeMobileScroll) {
        gsap.to(mock, {
          y: -40,
          ease: "none",
          scrollTrigger: { trigger: ".hero", start: "top top", end: "bottom 40%", scrub: true },
        });
      }
    }

    // Pointer tilt on the hero monitor (independent of GSAP).
    if (mock && finePointer && !reduceMotion) {
      const img = mock.querySelector("img");
      mock.addEventListener("pointermove", (e) => {
        const r = mock.getBoundingClientRect();
        const nx = (e.clientX - r.left) / r.width - 0.5;
        const ny = (e.clientY - r.top) / r.height - 0.5;
        img.style.setProperty("--ry", (nx * 5).toFixed(2) + "deg");
        img.style.setProperty("--rx", (-ny * 4).toFixed(2) + "deg");
      });
      mock.addEventListener("pointerleave", () => {
        img.style.setProperty("--rx", "0deg");
        img.style.setProperty("--ry", "0deg");
      });
    }
  }

  // ---- Journey: pinned stage where the three view-assist renders trade places ----
  function initJourney() {
    const journey = document.querySelector(".journey");
    const pin = document.getElementById("journey-pin");
    const stage = document.getElementById("journey-stage");
    if (!journey || !pin || !stage) return;

    // Without GSAP or with reduced motion: unpin into a static stacked
    // showcase, each caption directly under its render.
    if (!hasGsap || reduceMotion || nativeMobileScroll) {
      journey.classList.add("journey--static");
      journey.querySelectorAll(".journey__panel").forEach((p) => {
        const shot = stage.querySelector('.journey__shot[data-shot="' + p.dataset.panel + '"]');
        if (shot) shot.after(p);
      });
      journey.querySelectorAll(".journey__shot, .journey__panel").forEach((el) => {
        el.classList.add("is-active");
      });
      return;
    }

    const shots = Array.from(stage.querySelectorAll(".journey__shot"));
    const panels = Array.from(journey.querySelectorAll(".journey__panel"));
    const show = (name) => {
      shots.forEach((s) => s.classList.toggle("is-active", s.dataset.shot === name));
      panels.forEach((p) => p.classList.toggle("is-active", p.dataset.panel === name));
    };
    show("falsecolor");

    const tl = gsap.timeline({
      defaults: { ease: "none" },
      scrollTrigger: {
        trigger: journey,
        start: "top top",
        end: "bottom bottom",
        scrub: 1,
        pin: pin,
        anticipatePin: 1,
      },
    });

    // Stage settles in, each shot gets a slow breathe while it holds, and
    // the class-based crossfades land at the quarters. Each swap is a pair:
    // the first callback restores the outgoing phase when scrubbing back,
    // the second advances when scrubbing forward.
    tl.fromTo(stage, { scale: 0.92, y: 30 }, { scale: 1, y: 0, duration: 0.1 }, 0);
    tl.fromTo(shots[0], { scale: 1.0 }, { scale: 1.025, duration: 0.2 }, 0.03);
    tl.add(() => show("falsecolor"), 0.24);
    tl.add(() => show("trafficlights"), 0.255);
    tl.fromTo(shots[1], { scale: 1.0 }, { scale: 1.025, duration: 0.2 }, 0.27);
    tl.add(() => show("trafficlights"), 0.49);
    tl.add(() => show("peaking"), 0.505);
    tl.fromTo(shots[2], { scale: 1.0 }, { scale: 1.025, duration: 0.2 }, 0.52);
    tl.add(() => show("peaking"), 0.74);
    tl.add(() => show("markers"), 0.755);
    tl.fromTo(shots[3], { scale: 1.0 }, { scale: 1.025, duration: 0.2 }, 0.77);
    tl.to(stage, { scale: 0.97, duration: 0.05 }, 0.95);

    // Refresh pin offsets after resizes.
    let resizeTimer;
    window.addEventListener("resize", () => {
      clearTimeout(resizeTimer);
      resizeTimer = setTimeout(() => ScrollTrigger.refresh(), 200);
    });
  }

  // ---- Feature rows: copy staggers in, device settles with a slight organic tilt ----
  function initRows() {
    if (!hasGsap || reduceMotion) return;
    document.querySelectorAll(".feat-section").forEach((sec) => {
      const copy = sec.querySelectorAll(".feat-row__copy > *");
      const visual = sec.querySelector(".feat-row__visual");
      const stacked = sec.querySelector(".feat-row--stack");
      const fromLeft = !sec.querySelector(".feat-row--reverse");
      const portrait = sec.querySelector("img.is-portrait");
      const restRot = stacked ? 0 : portrait ? (fromLeft ? 2.2 : -2.2) : 0;
      if (copy.length) {
        gsap.from(copy, {
          opacity: 0,
          y: 22,
          duration: 0.8,
          ease: "expo.out",
          stagger: 0.08,
          scrollTrigger: { trigger: sec, start: "top 78%" },
        });
      }
      if (visual) {
        const shots = visual.querySelectorAll("img");
        const targets = shots.length ? shots : [visual];
        // Don't transform the visual wrapper — iOS clips filter:drop-shadow
        // on a child when the parent has a transform.
        if (nativeMobileScroll) {
          gsap.from(targets, {
            opacity: 0,
            y: 18,
            duration: 0.7,
            ease: "power3.out",
            stagger: 0.06,
            scrollTrigger: { trigger: sec, start: "top 82%" },
          });
        } else {
          gsap.fromTo(
            targets,
            {
              opacity: 0,
              x: stacked ? 0 : fromLeft ? 48 : -48,
              y: stacked ? 32 : 28,
              rotate: stacked ? 0 : restRot + (fromLeft ? 5 : -5),
              scale: stacked ? 0.96 : 0.92,
            },
            {
              opacity: 1,
              x: 0,
              y: 0,
              rotate: restRot,
              scale: 1,
              duration: 1.05,
              ease: "expo.out",
              stagger: 0.08,
              scrollTrigger: { trigger: sec, start: "top 80%" },
            }
          );
          gsap.to(targets, {
            yPercent: -5,
            ease: "none",
            scrollTrigger: {
              trigger: sec,
              start: "top bottom",
              end: "bottom top",
              scrub: true,
            },
          });
        }
      }
    });

    // The remaining quiet sections keep the simple rise-in.
    gsap.utils.toArray(".section:not(.feat-section)").forEach((sec) => {
      gsap.from(sec, {
        opacity: 0,
        y: 30,
        duration: 0.7,
        ease: "power3.out",
        scrollTrigger: { trigger: sec, start: "top 85%" },
      });
    });
  }

  function init() {
    initAnchors();
    initNavMorph();
    initSpotlight();
    initMagnetic();
    initHero();
    initJourney();
    initRows();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
