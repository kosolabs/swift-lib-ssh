# Changelog

## [1.5.0](https://github.com/kosolabs/swift-lib-ssh/compare/v1.4.0...v1.5.0) (2026-02-08)


### Features

* add support for no auth ([#70](https://github.com/kosolabs/swift-lib-ssh/issues/70)) ([a4e8c3c](https://github.com/kosolabs/swift-lib-ssh/commit/a4e8c3cd1f35f76f36fd60f7dc5bcf620ba62320))


### Bug Fixes

* reorganize code a little ([#68](https://github.com/kosolabs/swift-lib-ssh/issues/68)) ([4eafc48](https://github.com/kosolabs/swift-lib-ssh/commit/4eafc483804e05f94ce1f5c2772a66002a46f6c8))

## [1.4.0](https://github.com/kosolabs/swift-lib-ssh/compare/v1.3.2...v1.4.0) (2026-02-05)


### Features

* add ability to read contents of a directory ([#66](https://github.com/kosolabs/swift-lib-ssh/issues/66)) ([e664141](https://github.com/kosolabs/swift-lib-ssh/commit/e664141702642bbf0d1f9e604c42a2239a77cb25))

## [1.3.2](https://github.com/kosolabs/swift-lib-ssh/compare/v1.3.1...v1.3.2) (2026-01-26)


### Bug Fixes

* make sftp attributes public ([#61](https://github.com/kosolabs/swift-lib-ssh/issues/61)) ([147fa39](https://github.com/kosolabs/swift-lib-ssh/commit/147fa390a6276abfb0ebf2ee83a53cba121d67a7))

## [1.3.1](https://github.com/kosolabs/swift-lib-ssh/compare/v1.3.0...v1.3.1) (2026-01-23)


### Bug Fixes

* restrict port numbers to UInt16 ([#59](https://github.com/kosolabs/swift-lib-ssh/issues/59)) ([93c309d](https://github.com/kosolabs/swift-lib-ssh/commit/93c309d033de8bb982bbe88229213c264a5d77f4))

## [1.3.0](https://github.com/kosolabs/swift-lib-ssh/compare/v1.2.0...v1.3.0) (2026-01-23)


### Features

* add support for base64 encoded private key ([#55](https://github.com/kosolabs/swift-lib-ssh/issues/55)) ([08d888d](https://github.com/kosolabs/swift-lib-ssh/commit/08d888dde14d124275e3ac34a89fd91e66ff5bd0))


### Bug Fixes

* add check for task cancellation ([#58](https://github.com/kosolabs/swift-lib-ssh/issues/58)) ([d746564](https://github.com/kosolabs/swift-lib-ssh/commit/d746564072403b40926d4d31799c8923d9f5494b))
* tweak values in flaky partial read of channel test ([#57](https://github.com/kosolabs/swift-lib-ssh/issues/57)) ([3c19adb](https://github.com/kosolabs/swift-lib-ssh/commit/3c19adbee822a338fa3f1cf1def8f32d8d5b6b64))

## [1.2.0](https://github.com/kosolabs/swift-lib-ssh/compare/v1.1.1...v1.2.0) (2026-01-22)


### Features

* add statically compiled libssh ([#53](https://github.com/kosolabs/swift-lib-ssh/issues/53)) ([a00785e](https://github.com/kosolabs/swift-lib-ssh/commit/a00785eabdf4e6bef1926ff8ab50bc1b3fa87387))

## [1.1.1](https://github.com/kosolabs/swift-lib-ssh/compare/v1.1.0...v1.1.1) (2026-01-18)


### Bug Fixes

* update tests to use scoped resource ([#51](https://github.com/kosolabs/swift-lib-ssh/issues/51)) ([ad3a8d3](https://github.com/kosolabs/swift-lib-ssh/commit/ad3a8d3a5bbf4aedad47d2d6823b8717a21ca858))

## [1.1.0](https://github.com/kosolabs/swift-lib-ssh/compare/v1.0.1...v1.1.0) (2026-01-17)


### Features

* provide SSHClient as a scoped resource ([#50](https://github.com/kosolabs/swift-lib-ssh/issues/50)) ([175cf7e](https://github.com/kosolabs/swift-lib-ssh/commit/175cf7ed35895cdcff6fedab677d5dc3bf6699c9))


### Bug Fixes

* use environment and drop tagging code ([#48](https://github.com/kosolabs/swift-lib-ssh/issues/48)) ([4146b88](https://github.com/kosolabs/swift-lib-ssh/commit/4146b887c5433e0d61cc6e4d22ba83a4382e2bf8))

## [1.0.1](https://github.com/kosolabs/swift-lib-ssh/compare/v1.0.0...v1.0.1) (2026-01-16)


### Bug Fixes

* release please take 2 ([#46](https://github.com/kosolabs/swift-lib-ssh/issues/46)) ([37ff3c0](https://github.com/kosolabs/swift-lib-ssh/commit/37ff3c0f368a7f9f6995599286a0248064e63f90))

## 1.0.0 (2026-01-15)


### Features

* add exit code and stderr support to execute ([#42](https://github.com/kosolabs/swift-lib-ssh/issues/42)) ([570b9a6](https://github.com/kosolabs/swift-lib-ssh/commit/570b9a6f6c3c49b16bc6bd4a0b80469d7230919e))
* add progress callback to upload ([#32](https://github.com/kosolabs/swift-lib-ssh/issues/32)) ([7dd6581](https://github.com/kosolabs/swift-lib-ssh/commit/7dd6581e6f4f43f8b7f9ea1dcba331d4c1d50157))
* add support for streaming writes ([#39](https://github.com/kosolabs/swift-lib-ssh/issues/39)) ([774b1ea](https://github.com/kosolabs/swift-lib-ssh/commit/774b1ea4f16e1bbd931c013d1eea1ea11a197396))
* enable release please ([#44](https://github.com/kosolabs/swift-lib-ssh/issues/44)) ([947e554](https://github.com/kosolabs/swift-lib-ssh/commit/947e55435dbbfedbe47c0e9bc3cea673b06c67ca))
* implement read offset and read length ([#33](https://github.com/kosolabs/swift-lib-ssh/issues/33)) ([172aa48](https://github.com/kosolabs/swift-lib-ssh/commit/172aa48b228f2b62266699c23d99544bd82be9a2))
* initial implementation of upload ([#30](https://github.com/kosolabs/swift-lib-ssh/issues/30)) ([1d14a45](https://github.com/kosolabs/swift-lib-ssh/commit/1d14a45770ad0647726e69530844fd216c9666d8))


### Bug Fixes

* add [@shadanan](https://github.com/shadanan) as codeowner ([#37](https://github.com/kosolabs/swift-lib-ssh/issues/37)) ([f6f5c35](https://github.com/kosolabs/swift-lib-ssh/commit/f6f5c352e001721a7ab81c791b7f365bde28c057))
* allow renovate to manage pinned version ([#38](https://github.com/kosolabs/swift-lib-ssh/issues/38)) ([0e418e8](https://github.com/kosolabs/swift-lib-ssh/commit/0e418e8b3b14815ada46132f2844d43238e854fa))
* avoid second allocation of Data ([#31](https://github.com/kosolabs/swift-lib-ssh/issues/31)) ([0bc62b7](https://github.com/kosolabs/swift-lib-ssh/commit/0bc62b736b44d7341761d5326547e3a1529b9a78))
* remove dead code ([#29](https://github.com/kosolabs/swift-lib-ssh/issues/29)) ([2e95ba9](https://github.com/kosolabs/swift-lib-ssh/commit/2e95ba91aebf55196511ee0ce3e51e1a606da449))
* remove untested code ([#41](https://github.com/kosolabs/swift-lib-ssh/issues/41)) ([cff193a](https://github.com/kosolabs/swift-lib-ssh/commit/cff193a95b73c889d8280855e3c976204f5a0a91))
* simplify channel session management ([#43](https://github.com/kosolabs/swift-lib-ssh/issues/43)) ([2ca78a3](https://github.com/kosolabs/swift-lib-ssh/commit/2ca78a38f6872fc994db57f0a1775bca00a9fb30))
* tidy up naming ([#40](https://github.com/kosolabs/swift-lib-ssh/issues/40)) ([78b680b](https://github.com/kosolabs/swift-lib-ssh/commit/78b680b7d41f1f2725260f8f18636e82c2d9d53f))
