# Contributing to CLIX

Thanks for your interest in contributing to CLIX! This document covers how to contribute and how releases are made.

## Ways to Contribute

### Package Installation Guides

The easiest way to contribute is adding package installation guides for software that requires special NixOS configuration.

1. Create a new file in `docs/packages/<package-name>.md`
2. Follow the template in `docs/packages/README.md`
3. Include:
   - Why special configuration is needed
   - The exact NixOS configuration to add
   - Step-by-step installation instructions
   - Troubleshooting tips
4. Update `docs/packages/README.md` with a link to your guide
5. Submit a pull request

### Bug Reports

Open an issue on GitHub with:
- What you expected to happen
- What actually happened
- Steps to reproduce
- CLIX version (or commit hash)
- Hardware details if relevant

### Feature Requests

Open an issue describing the feature and why it would be useful for CLIX users.

### Code Contributions

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test locally (see Development Setup below)
5. Submit a pull request

## Development Setup

### Prerequisites

**Docker (recommended):**
```bash
# No additional setup needed - builds run in container
./scripts/docker-build.sh
```

**Native Nix:**
```bash
# Install Nix with flakes enabled
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf

# Build (requires root for correct file ownership)
sudo ./scripts/build-image.sh
```

### Testing

```bash
# Build the image
./scripts/docker-build.sh

# Test in QEMU (requires KVM and OVMF)
./scripts/test-vm.sh

# Test with more resources
CLIX_MEMORY=8G CLIX_CPUS=4 ./scripts/test-vm.sh
```

### Project Structure

- `modules/` - NixOS modules that define the system
- `config/` - Configuration files (sway, waybar, etc.)
- `scripts/` - Build and utility scripts
- `docs/packages/` - Package installation guides
- `examples/` - Example configuration files

## Release Process

CLIX uses GitHub Actions for automated releases.

### Creating a Release

1. **Update version references** (if any)

2. **Create and push a version tag:**
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

3. **GitHub Actions automatically:**
   - Builds the disk image using Docker
   - Compresses it as `clix-x86_64.img.zip`
   - Creates a GitHub Release with auto-generated release notes
   - Attaches the image to the release

### Version Numbering

We use semantic versioning:
- **Major** (v2.0.0): Breaking changes to user-facing behavior
- **Minor** (v1.1.0): New features, backward compatible
- **Patch** (v1.0.1): Bug fixes

### Manual Builds

You can trigger a build manually without creating a release:
1. Go to Actions → "Build CLIX Image"
2. Click "Run workflow"
3. The artifact will be available for download (7 day retention)

## Code Style

- **Nix**: Follow nixpkgs conventions
- **Shell scripts**: Use shellcheck, quote variables
- **Documentation**: Clear, concise, with examples

## Questions?

Open an issue or discussion on GitHub.
