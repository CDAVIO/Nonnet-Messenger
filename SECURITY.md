# Security Policy

## Supported versions

| Version | Supported |
|:--|:--|
| 1.0 (latest) | ✅ |

## Reporting a vulnerability

Please **don't open a public issue** for security problems.

Report it privately through **GitHub → Security → Report a vulnerability** on this repository (private vulnerability reporting). Include the device, iOS/macOS version, the steps to reproduce, and the impact you expect.

You'll get an answer as soon as possible, and fixed issues are credited in the release notes if you want.

## Security model

**What NonNet protects**

- **No servers.** Messages, photos and videos go directly between devices over Bluetooth Low Energy (L2CAP). Nothing is uploaded or stored online.
- **End-to-end encryption per connection.** When two devices connect, each creates a fresh **X25519** key pair. The shared secret goes through **HKDF-SHA256**, and every message, receipt, location update and media file is sealed with **ChaChaPoly** (CryptoKit).
- **No identity data on the air.** Devices advertise only a random 4-character code that changes on every launch. No name, phone number, email, IP address or account exists.
- **Ephemeral by default.** Chats live in memory, and received media is stored in the app's cache, which is wiped at launch. **1X** media is deleted on the receiving device as soon as the viewer closes.
- **Location** is shared only with connected NonNet devices, only while the app runs, and can be turned off in Settings.

**Known limitations**

- **No identity verification yet.** Keys aren't verified out of band (no safety-number comparison), so an active attacker within Bluetooth range could in theory sit in the middle of a new connection. Treat NonNet as private against passive listening, not as a replacement for verified-identity messengers.
- **Nicknames aren't authenticated.** Anyone can choose any nickname.
- **Screenshots and screen recording** of 1X media can't be blocked by iOS apps.
- **Metadata:** people nearby can see that a NonNet device is present (the service UUID and Bluetooth signal), though not who it is.
- **Denial of service:** like any radio protocol, Bluetooth can be jammed.

## Scope

In scope: the app source in this repository (transport, encryption, media handling, storage).
Out of scope: vulnerabilities in iOS, macOS or Apple's Bluetooth stack (report those to Apple), and physical access to an unlocked device.
