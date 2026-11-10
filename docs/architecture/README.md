# Architecture diagram

`kazokuai.src.html` is the source of the diagram, written for the `stack-diagram` skill. `kazokuai.html`, `kazokuai.png`, and `kazokuai-dark.png` are built from it: rebuild them instead of editing them.

The diagram shows what the repository builds and runs today, and the 電話機's Raspberry Pi, which the device program is built for. Any other component that is only planned, in an ADR or a spec, joins the diagram in the PR that builds it.

## Updating the diagram

Run the commands below in `docs/architecture/`. `<skill>` is the folder of the `stack-diagram` skill.

1. Edit the groups, edges, and nodes in `kazokuai.src.html`, following the skill's geometry rules. Update the kicker's date.
2. Fetch the icons into a folder outside the repository. Google Cloud's icons may not be redistributed, so never commit the icon files.

   ```bash
   python3 <skill>/scripts/fetch_icons.py <icons> "phone:lucide/phone" "home:lucide/house" "smartphone:lucide/smartphone" \
     "raspberrypi:raspberry-pi" gemini flutter firebase github "sa:lucide/key-round" "gcp:google-cloud" "run:gcp/cloud-run" \
     "secret:gcp/secret-manager" "hosting:firebase" "ar:gcp/artifact-registry" "iam:gcp/identity-and-access-management" \
     "tasks:gcp/cloud-tasks"
   cp <skill>/assets/generic/user.svg <icons>/person.svg
   ```

3. Build the HTML, then render both PNGs and look at them before you commit.

   ```bash
   python3 <skill>/scripts/build.py kazokuai.src.html <icons> kazokuai.html --fonts <skill>/assets/fonts
   uv run --with playwright python <skill>/scripts/render_png.py kazokuai.html kazokuai.png --selector .canvas --scale 2
   ```

   The first render needs Chromium: `uv run --with playwright playwright install chromium`.
