# Validation

The project was validated in the sandbox with the included test script:

```bash
cd RayLite
./tests/validate.sh
```

Observed result:

```text
[PASS] bash syntax
[PASS] help output
[PASS] dry-run preview files
[PASS] generated JSON is valid
[PASS] client-only VMess link decodes correctly
[PASS] Debian -> apt
[PASS] Ubuntu -> apt
[PASS] Fedora -> dnf
[PASS] Rocky -> dnf
[PASS] Arch -> pacman
[PASS] openSUSE -> zypper
[PASS] all validation tests completed
```

What was checked:

- Bash syntax check for `setup-raylite.sh`
- Help output
- Dry-run deployment with preview file generation under a temporary root
- Generated V2Ray server JSON validity
- Generated VMess share JSON validity
- VMess import link base64 decoding and JSON equality check
- Client-only mode
- Distribution mapping tests:
  - Debian -> apt
  - Ubuntu -> apt
  - Fedora -> dnf
  - Rocky Linux -> dnf
  - Arch Linux -> pacman
  - openSUSE -> zypper

The sandbox did not run a real package installation, Certbot request, Nginx reload, or V2Ray service start because those operations require a real root VPS environment, public DNS, open ports, and systemd.
