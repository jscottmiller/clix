Claude Authentication
=====================

On first boot, run `claude` in the terminal and sign in through Firefox.
Your credentials will be saved to your encrypted home directory.

Claude Settings
===============

The settings.json file in this folder controls which commands Claude can
run without asking for permission. It's moved to ~/.claude/ on first boot.

To customize permissions before first boot, edit:
  CLIX-PUBLIC/clix/claude/settings.json

After first boot, edit:
  ~/.claude/settings.json
