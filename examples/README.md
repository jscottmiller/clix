# CLIX Configuration Examples

These example files show how to configure the CLIX-PUBLIC partition for automatic setup on boot.

## Directory Structure

The CLIX-PUBLIC partition (FAT32, labeled `CLIX-PUBLIC`) expects this structure:

```
CLIX-PUBLIC/
├── clix/
│   ├── network/
│   │   ├── regdomain             # WiFi regulatory domain (e.g., "US")
│   │   └── *.nmconnection        # NetworkManager connection files
│   └── claude/
│       └── settings.json         # Claude permissions (edit before first boot)
└── README.txt                    # (auto-generated on partition)
```

## Network Configuration

### Regulatory Domain (Required for WiFi)

Create `clix/network/regdomain` containing your 2-letter country code:

```
US
```

Common codes: US, GB, DE, FR, JP, AU, CA. This is required for WiFi to function properly.

### WiFi/Ethernet Connections

Place NetworkManager connection files in the `clix/network/` directory. Files must:
- Have the `.nmconnection` extension
- Be valid NetworkManager keyfile format

### Examples provided:

| File | Description |
|------|-------------|
| `regdomain` | Regulatory domain example (US) |
| `wifi-example.nmconnection` | Basic WPA2 Personal WiFi |
| `wifi-enterprise.nmconnection` | WPA2 Enterprise (802.1X) |
| `ethernet-static.nmconnection` | Static IP ethernet |

### Creating your own

1. Copy an example and rename it
2. Generate a new UUID: `uuidgen`
3. Update the `id`, `uuid`, `ssid`, and credentials

### Exporting from existing system

On a Linux machine with NetworkManager:
```bash
# List connections
nmcli connection show

# Connection files are in:
ls /etc/NetworkManager/system-connections/

# Copy the one you want (as root)
sudo cp /etc/NetworkManager/system-connections/MyWiFi.nmconnection ./network/
```

## Claude Authentication

On first boot, run `claude` in the terminal and sign in through Firefox. Your credentials will be saved to your encrypted home directory.

## Writing to the Data Partition

After writing the CLIX image to USB, the CLIX-PUBLIC partition will be the **first** partition (designed for Windows visibility):

**On Linux:**
```bash
# Find partitions (replace sdX with your USB device)
lsblk /dev/sdX

# Mount the data partition (partition 1)
sudo mount /dev/sdX1 /mnt

# Copy your configs
sudo mkdir -p /mnt/clix
sudo cp -r network/ /mnt/clix/

# Unmount
sudo umount /mnt
```

**On Windows:** The CLIX-PUBLIC partition should appear as a drive letter automatically after writing the image. Just open it in Explorer and copy your files.
