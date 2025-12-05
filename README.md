# SwiftLibSSH

A Swift library that wraps `libssh`.

## Installation

Add this package to your `Package.swift`:

```swift
.package(url: "https://github.com/kosolabs/swift-lib-ssh.git", branch: "main")
```

Then add the dependency to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: ["SwiftLibSSH"]
)
```

## Quick Start

### Connect with SSH Agent or Default Keys

```swift
import SwiftLibSSH

let client = try SSHClient.connect(
    host: "example.com",
    user: "username"
)

let output = try client.execute("ls -la")
print(output)

client.close()
```

### Connect with Password

```swift
let client = try SSHClient.connect(
    host: "example.com",
    user: "username",
    password: "password"
)

let output = try client.execute("whoami")
print(output)

client.close()
```

### Connect with Private Key

```swift
let client = try SSHClient.connect(
    host: "example.com",
    user: "username",
    privateKeyPath: "/path/to/id_rsa"
)

let output = try client.execute("uname -a")
print(output)

client.close()
```

### Connect with Encrypted Private Key

```swift
let client = try SSHClient.connect(
    host: "example.com",
    user: "username",
    privateKeyPath: "/path/to/id_rsa",
    passphrase: "your_passphrase"
)

let output = try client.execute("pwd")
print(output)

client.close()
```

## Authentication Methods

### 1. SSH Agent (Default)
When connecting without specifying credentials, the client attempts to authenticate using:
1. SSH agent (if available)
2. Default key locations:
   - `~/.ssh/id_rsa`
   - `~/.ssh/id_ecdsa`
   - `~/.ssh/id_ed25519`
   - `~/.ssh/id_dsa`

### 2. Private Key
Authenticate using a specific private key file, with optional passphrase support for encrypted keys.

### 3. Password
Authenticate using plaintext password authentication (use with caution over untrusted networks).

## API Reference

### SSHClient

The main class for SSH operations.

#### Static Methods

- `connect(host:port:user:) -> SSHClient` - Connect with SSH agent or default keys
- `connect(host:port:user:password:) -> SSHClient` - Connect with password
- `connect(host:port:user:privateKeyPath:passphrase:) -> SSHClient` - Connect with private key

#### Instance Methods

- `execute(_:) -> String` - Execute a command and return output
- `close()` - Close the SSH connection

#### Properties

- `connected: Bool` - Check if currently connected

### SSHClientError

Error enum with the following cases:

- `connectionFailed(String)` - Failed to connect to the SSH server
- `authenticationFailed(String)` - Authentication failed
- `sessionError(String)` - SSH session operation failed
- `channelError(String)` - SSH channel operation failed

## Error Handling

All operations can throw `SSHClientError`. It's recommended to use do-catch blocks:

```swift
do {
    let client = try SSHClient.connect(host: "example.com", user: "username")
    let output = try client.execute("ls -la")
    print(output)
    client.close()
} catch SSHClientError.connectionFailed(let error) {
    print("Connection failed: \(error)")
} catch SSHClientError.authenticationFailed(let error) {
    print("Authentication failed: \(error)")
} catch SSHClientError.channelError(let error) {
    print("Channel error: \(error)")
} catch SSHClientError.sessionError(let error) {
    print("Session error: \(error)")
} catch {
    print("Unknown error: \(error)")
}
```

## Custom Port

By default, connections use port 22. You can specify a custom port:

```swift
let client = try SSHClient.connect(
    host: "example.com",
    port: 2222,
    user: "username"
)
```

## Connection Lifecycle

The SSH client automatically manages connection cleanup through its deinitializer, but it's recommended to explicitly call `close()` when done:

```swift
let client = try SSHClient.connect(host: "example.com", user: "username")
defer {
    client.close()
}

let output = try client.execute("your command")
```

## Testing

The project includes functional tests with an SSH test server. To run tests:

```bash
swift test
```

Tests use Docker to run a test SSH server. Ensure Docker is installed and running.

## Requirements Details

### Dependencies

- **CLibSSH**: System library wrapper for libssh
  - Provides bridging between Swift and C libssh API
  - Automatically installed via Homebrew on macOS

### Platform Support

- macOS 10.15 Catalina or later

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

## Implementation Notes

- Command output is read in 1024-byte chunks until EOF
- Only stdout is captured (stderr is typically merged by the remote shell)
- SSH sessions are automatically closed and freed when the client is deallocated
- The library wraps libssh for low-level SSH protocol handling

## Troubleshooting

### Connection Refused
- Verify the host and port are correct
- Check that SSH server is running on the remote host
- Ensure firewall rules allow SSH connections

### Authentication Failed
- Verify the username is correct
- For key authentication, ensure the key file exists and has proper permissions
- For SSH agent, verify `ssh-add` has loaded your keys

### No Such File or Directory
- Verify the private key path is absolute and correct
- Check that the file has read permissions

### libssh Not Found
On macOS, install libssh via Homebrew:
```bash
brew install libssh
```

## Support

For issues and questions, please open an issue on the GitHub repository.
