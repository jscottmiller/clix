# CLIX Package Installation Guides

Some packages on NixOS require special configuration beyond a simple `nix profile install`. This folder contains guides for installing such packages on CLIX.

## Available Guides

- [Steam](steam.md) - Gaming platform with FHS sandbox requirements

## Contributing

To add a guide for a new package:

1. Create a new `<package-name>.md` file in this folder
2. Include:
   - Why special configuration is needed
   - The exact NixOS configuration to add
   - Any post-install steps
   - Troubleshooting tips
3. Update this README with a link to your guide
4. Submit a pull request

## Guide Template

```markdown
# Package Name

## Why Special Configuration?
Explain why `nix profile install` won't work.

## Configuration
\`\`\`nix
# Add to /etc/nixos/configuration.nix
\`\`\`

## Installation Steps
1. Edit configuration
2. Run rebuild
3. Any post-install steps

## Troubleshooting
Common issues and solutions.
```
