# Auto-Rotate Display

## Why Special Configuration?

2-in-1 laptops (like the Lenovo IdeaPad Flex series) have a built-in
accelerometer that detects physical orientation. This guide sets up automatic
screen rotation in Sway so the display follows the device when you flip the
laptop.

The setup reads directly from the Linux IIO (Industrial I/O) subsystem. We
cannot use `iio-sensor-proxy` because it crashes on BMA250E HID sensors (common
in Lenovo Flex laptops) with "Not a switch" errors. Instead, a Python script
reads the IIO character device (`/dev/iio:device0`) which provides live data.

**Note on HID sensors:** The sysfs raw files (`in_accel_x_raw`, etc.) cache
their values on HID-based accelerometers and do not update in real time. You
must read from the character device with the IIO buffer enabled to get live
data.

## Prerequisites

Verify your device has an accelerometer:

```bash
ls /sys/bus/iio/devices/iio:device*/in_accel_x_raw
```

If this returns a path, you have the hardware. If not, your device doesn't have
an accelerometer and this guide won't work.

Check if it's a HID sensor (determines which approach to use):

```bash
readlink -f /sys/bus/iio/devices/iio:device0
```

If the path contains `HID-SENSOR`, you have a HID-based accelerometer and must
use the character device approach described here. If it's a direct I2C/SPI
device, `iio-sensor-proxy` with `monitor-sensor` may work instead (simpler
setup, not covered here).

## Configuration

Add to `/etc/nixos/configuration.nix`:

```nix
{ config, pkgs, lib, ... }:

{
  # Auto-rotate support (installs iio-sensor-proxy and loads IIO modules)
  hardware.sensor.iio.enable = true;

  # Allow user access to the IIO accelerometer device
  services.udev.extraRules = ''
    SUBSYSTEM=="iio", KERNEL=="iio:device*", MODE="0666"
  '';
}
```

## Installation Steps

1. Edit the configuration:
   ```bash
   edit-config
   ```

2. Add the configuration above

3. Rebuild the system:
   ```bash
   rebuild
   ```

4. Apply the udev rule to the existing device:
   ```bash
   sudo udevadm trigger --subsystem-match=iio
   ```

5. Verify the device is accessible:
   ```bash
   ls -la /dev/iio:device0
   # Should show crw-rw-rw- permissions
   ```

6. Create the auto-rotate script at `~/.local/bin/sway-autorotate`:
   ```bash
   mkdir -p ~/.local/bin
   ```

   Write the following to `~/.local/bin/sway-autorotate`:

   ```python
   #!/usr/bin/env python3
   """Auto-rotate Sway output based on accelerometer orientation.

   Reads the accelerometer from the IIO character device
   (/dev/iio:device0) which provides live data, unlike the sysfs
   raw files which cache values on HID sensors.
   """

   import struct
   import os
   import subprocess
   import time

   DEVICE = "/dev/iio:device0"
   SYSFS = "/sys/bus/iio/devices/iio:device0"
   OUTPUT = "eDP-1"
   THRESHOLD = 500
   # Sample size: 3 axes x 4 bytes each (s16 in 32-bit storage, little-endian)
   SAMPLE_SIZE = 12


   def enable_buffer():
       """Enable IIO scan elements and buffer for live char device reads.

       The IIO buffer must be enabled before the character device will
       produce data. The scan elements select which channels to read,
       and the trigger determines when samples are taken.
       """
       subprocess.run(["sudo", "bash", "-c",
           f"echo 0 > {SYSFS}/buffer/enable 2>/dev/null;"
           f"echo 1 > {SYSFS}/scan_elements/in_accel_x_en;"
           f"echo 1 > {SYSFS}/scan_elements/in_accel_y_en;"
           f"echo 1 > {SYSFS}/scan_elements/in_accel_z_en;"
           f"echo accel_3d-dev0 > {SYSFS}/trigger/current_trigger;"
           f"echo 1 > {SYSFS}/buffer/enable"
       ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


   def get_orientation(x, y):
       """Determine screen orientation from accelerometer X and Y axes."""
       if abs(y) > abs(x):
           if y < -THRESHOLD:
               return "0"       # Normal upright
           elif y > THRESHOLD:
               return "180"     # Upside down
       else:
           if x < -THRESHOLD:
               return "90"      # Left side down
           elif x > THRESHOLD:
               return "270"     # Right side down
       return None


   def swaymsg(*args):
       """Run a swaymsg command."""
       subprocess.run(
           ["swaymsg"] + list(args),
           stdout=subprocess.DEVNULL,
           stderr=subprocess.DEVNULL,
       )


   # Calibration matrices for touch input in each rotation.
   # Sway's map_to_output handles tap position correctly for all rotations,
   # but touch scroll direction needs correction via calibration matrix.
   #
   # For 90° and 270°, the matrix rotates touch coordinates to match the
   # rotated output. For 180°, Sway handles X-axis scroll correctly but
   # inverts Y-axis scroll, so we only invert Y.
   CALIBRATION = {
       "0":   "1 0 0 0 1 0",       # identity
       "90":  "0 1 0 -1 0 1",      # 90°
       "180": "1 0 0 0 -1 1",      # invert Y only
       "270": "0 -1 1 1 0 0",      # 270°
   }


   def set_transform(transform):
       """Apply rotation transform to Sway output and adjust touch input."""
       swaymsg("output", OUTPUT, "transform", transform)
       # Apply calibration matrix to fix touch scroll direction
       matrix = CALIBRATION[transform]
       swaymsg("input", "type:touch", "calibration_matrix", matrix)


   def main():
       enable_buffer()
       fd = os.open(DEVICE, os.O_RDONLY)
       current = None

       try:
           while True:
               data = os.read(fd, SAMPLE_SIZE)
               if len(data) < SAMPLE_SIZE:
                   time.sleep(1)
                   continue

               x = struct.unpack_from("<h", data, 0)[0]
               y = struct.unpack_from("<h", data, 4)[0]

               orientation = get_orientation(x, y)
               if orientation and orientation != current:
                   set_transform(orientation)
                   current = orientation

               time.sleep(0.5)
       finally:
           os.close(fd)


   if __name__ == "__main__":
       main()
   ```

   Make it executable:
   ```bash
   chmod +x ~/.local/bin/sway-autorotate
   ```

   **Note:** The script targets `eDP-1` (the built-in display). If your output
   has a different name, check with `swaymsg -t get_outputs` and adjust
   accordingly.

7. Add to sway autostart. Edit `~/.config/sway/config` and add:
   ```
   # Auto-rotate display based on accelerometer
   exec ~/.local/bin/sway-autorotate
   ```

8. Start it now without restarting sway:
   ```bash
   ~/.local/bin/sway-autorotate &
   ```

## Usage

Once running, the screen automatically rotates when you physically flip the
laptop. The script detects orientation based on accelerometer axis values
exceeding a threshold.

Touch tap position follows the display rotation automatically via Sway's
`map_to_output`. However, touch scroll direction requires a calibration matrix
correction — Sway does not fully transform scroll deltas when the output is
rotated. The script applies per-orientation calibration matrices to fix this.

## Known Limitations

### Tablet mode required for portrait rotation

On 2-in-1 laptops like the Lenovo Flex, the accelerometer only reports portrait
(90°/270°) orientations when the laptop is in tablet mode (lid folded past
180°). In normal laptop mode, the sensor firmware locks to landscape
orientations only, preventing accidental rotations while typing. The 180° flip
(upside down) works in both modes.

### Sensor data freezes

The IIO character device may stop producing data if:
- The buffer becomes disabled (e.g., after a suspend/resume cycle)
- Another process opens the device exclusively

If rotation stops working, restart the script:
```bash
pkill -f sway-autorotate
~/.local/bin/sway-autorotate &
```

## Troubleshooting

### Screen doesn't rotate at all

Check that the script is running:
```bash
pgrep -f sway-autorotate || ~/.local/bin/sway-autorotate &
```

Verify the IIO buffer is enabled:
```bash
cat /sys/bus/iio/devices/iio:device0/buffer/enable
# Should output: 1
```

### iio-sensor-proxy crashes

If you see logs like:
```
Not a switch [/sys/devices/.../HID-SENSOR-200073.2.auto/iio:device0/../capabilities/sw]
```

This is expected for HID sensors. The Python script bypasses iio-sensor-proxy
entirely. You still need `hardware.sensor.iio.enable = true` for the kernel
modules, but the iio-sensor-proxy service itself is not used.

### Rotation directions are wrong

The mapping between sensor axes and sway transform may vary by device. Edit
`~/.local/bin/sway-autorotate` and adjust the transform values in
`get_orientation()` until they match your device.

### Touch scroll direction is wrong after rotation

The calibration matrices in the script may need adjustment for your device.
Sway handles tap position via `map_to_output`, but scroll direction depends
on the calibration matrix. The matrices are 2D affine transforms specified as
6 values (`a b c d e f`) where `x' = ax + by + c` and `y' = dx + ey + f`.

Common adjustments:
- If scroll is inverted on one axis only, try negating just that axis
  (e.g., `1 0 0 0 -1 1` inverts Y only)
- If scroll axes are swapped, the rotation matrices (90°/270°) may need to
  be swapped with each other

### Touch taps land in the wrong place

Ensure your sway config maps touch to the output:
```
input type:touch map_to_output eDP-1
```

### Want to disable auto-rotate temporarily

```bash
pkill -f sway-autorotate
```

Restart when you want it back:
```bash
~/.local/bin/sway-autorotate &
```
