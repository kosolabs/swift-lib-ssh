# Keys

This folder contains the GPG keyrings used by [`build.sh`](../build.sh) to verify
the signatures (`.asc`) of the OpenSSL and libssh source tarballs before building
them (via `gpgv --keyring`).

- `openssl.gpg` — OpenSSL release signing keys
- `libssh.gpg` — libssh release signing key

## Regenerating

Download the public key(s) from the upstream project and convert them from
ASCII-armored format to the binary keyring format `gpgv` expects.

### OpenSSL

```sh
curl https://openssl-library.org/source/pubkeys.asc | gpg --dearmor > openssl.gpg
```

Source: https://openssl-library.org/source/

### libssh

```sh
curl https://www.libssh.org/files/0x03D5DF8CFDD3E8E7_libssh_libssh_org_gpgkey.asc | gpg --dearmor > libssh.gpg
```

Source: https://www.libssh.org/get-it/
