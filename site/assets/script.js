// The wipe, same as the app's: pointer position becomes --pos on the .diff element.
// No dependencies — this is the whole interactive surface of the site.
for (const diff of document.querySelectorAll(".diff")) {
  const move = (event) => {
    const rect = diff.getBoundingClientRect();
    const x = Math.min(Math.max(event.clientX - rect.left, 0), rect.width);
    diff.style.setProperty("--pos", (x / rect.width) * 100 + "%");
  };
  diff.addEventListener("pointerdown", (event) => {
    diff.setPointerCapture(event.pointerId);
    move(event);
  });
  diff.addEventListener("pointermove", (event) => {
    if (event.buttons) move(event);
  });
}

// Language dropdown closes on any outside click.
const lang = document.querySelector(".lang");
if (lang) {
  document.addEventListener("click", (event) => {
    if (!lang.contains(event.target)) lang.removeAttribute("open");
  });
}
