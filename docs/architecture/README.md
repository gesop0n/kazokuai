# Architecture diagram

`kazokuai.src.html` is the source of the diagram, written for the `stack-diagram` skill. `kazokuai.html`, `kazokuai.png`, and `kazokuai-dark.png` are built from it: rebuild them instead of editing them.

## Updating the diagram

Run the commands below in `docs/architecture/`. `<skill>` is the folder of the `stack-diagram` skill.

1. Edit the groups, edges, and nodes in `kazokuai.src.html`, following the skill's geometry rules. Update the kicker's date.
2. Fetch the icons into a folder outside the repository. Google Cloud's icons may not be redistributed, so never commit the icon files.

   ```bash
   python3 <skill>/scripts/fetch_icons.py <icons> "phone:lucide/phone" "home:lucide/house" "smartphone:lucide/smartphone" \
     "browser:lucide/globe" "raspberrypi:raspberry-pi" gemini flutter firebase "gcp:google-cloud" \
     "run:gcp/cloud-run" "tasks:gcp/cloud-tasks" "scheduler:gcp/cloud-scheduler" "secret:gcp/secret-manager" \
     "hosting:firebase"
   cp <skill>/assets/generic/user.svg <icons>/person.svg
   ```

3. Build the HTML, then render both PNGs and look at them before you commit.

   ```bash
   python3 <skill>/scripts/build.py kazokuai.src.html <icons> kazokuai.html --fonts <skill>/assets/fonts
   uv run --with playwright python <skill>/scripts/render_png.py kazokuai.html kazokuai.png --selector .canvas --scale 2
   ```

   The first render needs Chromium: `uv run --with playwright playwright install chromium`.
