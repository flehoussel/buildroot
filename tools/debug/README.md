# tools/debug

Standalone diagnostic scripts for the orangepi-z2w. They are not part of the
image: copy them to the board and run them directly, no rebuild needed.

- `measure-usb-load.sh` - CPU usage, musb-hdrc IRQ rate, WiFi throughput, CPU
  frequency and temperature during a session

## Copying the scripts to the board

`scp` needs an SFTP/SSH server on the board, and the root login must be
allowed with a password. Before building the image:

- enable OpenSSH in `orangepi-z2w_defconfig` (`BR2_PACKAGE_OPENSSH=y`, with
  `BR2_PACKAGE_OPENSSH_SERVER=y`; not set by default), which provides
  `sshd` and `sftp-server`;
- allow root login with a password (`PermitRootLogin yes` and
  `PasswordAuthentication yes` in `sshd_config`), and set a root password.

Then:

    scp tools/debug/*.sh root@<board-ip>:/tmp/
    ssh root@<board-ip> /tmp/measure-usb-load.sh start
