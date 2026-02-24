# CLIX Configuration Examples

These example files show how to configure the CLIX-DATA partition for automatic setup on boot.

## Directory Structure

The CLIX-DATA partition (FAT32, labeled `CLIX-DATA`) expects this structure:

```
CLIX-DATA/
├── network/
│   ├── regdomain             # WiFi regulatory domain (e.g., "US")
│   └── *.nmconnection        # NetworkManager connection files
└── README.txt                # (auto-generated on partition)
```

## Network Configuration

### Regulatory Domain (Required for WiFi)

Create `network/regdomain` containing your 2-letter country code:

```
US
```

Common codes: US, GB, DE, FR, JP, AU, CA. This is required for WiFi to function properly.

### WiFi/Ethernet Connections

Place NetworkManager connection files in the `network/` directory. Files must:
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

On first boot, run `claude` in the terminal and sign in through Firefox. Your credentials will be saved for the session (until reboot).

## Writing to the Data Partition

After writing the CLIX image to USB, the CLIX-DATA partition will be the **first** partition (designed for Windows visibility):

**On Linux:**
```bash
# Find partitions (replace sdX with your USB device)
lsblk /dev/sdX

# Mount the data partition (partition 1)
sudo mount /dev/sdX1 /mnt

# Copy your configs
sudo cp -r network/ /mnt/
sudo cp -r claude/ /mnt/

# Unmount
sudo umount /mnt
```

**On Windows:** The CLIX-DATA partition should appear as a drive letter automatically after writing the image. Just open it in Explorer and copy your files.
