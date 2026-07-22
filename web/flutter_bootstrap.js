// Startup + installed-PWA resume resilience (Phase 11.1 / 11.3).
//
// Browser-agnostic by construction: it listens to standard lifecycle events
// (visibilitychange, pageshow, webglcontextlost) and talks to Dart over
// versioned window events. Nothing here is keyed to Brave, Chromium, Firefox,
// or Android.
{{flutter_js}}
{{flutter_build_config}}

(function () {
  "use strict";

  var PROTOCOL = 1; // bump if the Dart<->JS event contract changes
  var RESUME_TIMEOUT_MS = 3000;   // wait for a rendered frame after resume
  var RECOVERY_KEY = "md_recovery_attempt";
  var boot = document.getElementById("boot");

  function setBoot(state) { if (boot) boot.setAttribute("data-state", state); }
  function hideBoot() { if (boot) boot.classList.add("hidden"); }
  function showBoot() { if (boot) boot.classList.remove("hidden"); }

  function log(event, ms) {
    // Privacy-safe: event name and duration only. No financial values, labels,
    // or message content ever pass through here (11.3).
    try { console.log("[lifecycle]", event, ms == null ? "" : ms + "ms"); } catch (e) {}
  }

  // A reload that busts both the release cache and any stale service worker,
  // so a broken shell cannot be served twice.
  window.__reloadFresh = function () {
    var url = new URL(window.location.href);
    url.searchParams.set("r", Date.now().toString());
    if ("serviceWorker" in navigator) {
      navigator.serviceWorker.getRegistrations().then(function (regs) {
        regs.forEach(function (r) { r.update(); });
        window.location.replace(url.toString());
      }).catch(function () { window.location.replace(url.toString()); });
    } else {
      window.location.replace(url.toString());
    }
  };

  var dartReady = false;
  var startedAt = Date.now();

  // --- Dart -> JS: the app is initialized and has painted a usable frame. ----
  window.addEventListener("md-dart-ready", function (e) {
    if (e.detail && e.detail.protocol !== PROTOCOL) {
      // A cached shell speaking an old contract: force a fresh copy once.
      if (!sessionStorage.getItem(RECOVERY_KEY)) {
        sessionStorage.setItem(RECOVERY_KEY, "protocol");
        window.__reloadFresh();
      }
      return;
    }
    dartReady = true;
    sessionStorage.removeItem(RECOVERY_KEY); // healthy frame clears the marker
    log("dart_ready", Date.now() - startedAt);
    hideBoot();
  });

  // --- Resume watchdog -------------------------------------------------------
  var pendingResume = null;

  function requestResume(reason) {
    if (!dartReady) return;              // still in first-load, not a resume
    if (pendingResume) return;           // ignore duplicate signals for one attempt
    var attemptId = reason + ":" + Date.now();
    pendingResume = attemptId;
    var t0 = Date.now();
    log("resume_request", 0);

    window.dispatchEvent(new CustomEvent("md-resume-request", {
      detail: { protocol: PROTOCOL, attemptId: attemptId },
    }));

    var timer = setTimeout(function () {
      if (pendingResume !== attemptId) return; // acked in time
      // No rendered frame within the window: recover once, then stop.
      log("resume_timeout", Date.now() - t0);
      if (sessionStorage.getItem(RECOVERY_KEY)) {
        // Second failure — do not loop. Show the manual recovery surface.
        setBoot("failed");
        showBoot();
        var code = document.getElementById("boot-code");
        if (code) code.textContent = "resume-stalled";
      } else {
        sessionStorage.setItem(RECOVERY_KEY, "resume");
        setBoot("recover");
        showBoot();
        window.__reloadFresh();
      }
    }, RESUME_TIMEOUT_MS);

    // Dart -> JS: a post-frame ack for this exact attempt.
    function onAck(ev) {
      if (!ev.detail || ev.detail.attemptId !== attemptId) return;
      clearTimeout(timer);
      pendingResume = null;
      window.removeEventListener("md-resume-ack", onAck);
      log("resume_ack", Date.now() - t0);
      hideBoot();
    }
    window.addEventListener("md-resume-ack", onAck);
  }

  document.addEventListener("visibilitychange", function () {
    if (document.visibilityState === "visible") requestResume("visible");
  });
  // pageshow with persisted=true is the bfcache restore path.
  window.addEventListener("pageshow", function (e) {
    if (e.persisted) requestResume("pageshow");
  });
  // WebGL context loss is the documented mobile-Brave blank-screen trigger (D8).
  window.addEventListener("webglcontextlost", function (e) {
    log("webgl_context_lost", 0);
    requestResume("webgl");
  }, true);

  // --- First-load safety net: if Dart never signals ready, don't hang. -------
  setTimeout(function () {
    if (dartReady) return;
    log("startup_timeout", Date.now() - startedAt);
    if (sessionStorage.getItem(RECOVERY_KEY)) {
      setBoot("failed");
      var code = document.getElementById("boot-code");
      if (code) code.textContent = "startup-stalled";
    } else {
      sessionStorage.setItem(RECOVERY_KEY, "startup");
      setBoot("recover");
      window.__reloadFresh();
    }
  }, 12000);

  // --- Load Flutter with its supported loader hooks. -------------------------
  _flutter.loader.load({
    onEntrypointLoaded: function (engineInitializer) {
      engineInitializer.initializeEngine().then(function (appRunner) {
        return appRunner.runApp();
      });
    },
  });
})();
