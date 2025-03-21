# Archangel: Advanced USB Encryption Session Manager

![Archangel Logo](https://raw.githubusercontent.com/username/archangel/master/logo.png)

Archangel provides military-grade encryption for your sensitive files on USB drives, using a secure RAM-based session model.

## Features

- **Triple-Layer Encryption**: Each file is encrypted with 3 layers of AES-256 encryption
- **RAM-Based Session**: Decrypted files only exist in RAM, never persisted to disk
- **Cross-Platform**: Works on macOS, Linux, and Windows (with limitations)
- **USB Ejection Detection**: Automatically wipes session if USB is removed
- **Secure File Handling**: Shreds files properly when deleted
- **Clipboard Encryption**: Securely encrypt/decrypt clipboard contents
- **Panic Mode**: Emergency session termination with a single keypress
- **File Integrity Verification**: SHA-256 checksums to verify file integrity
- **Encrypted Notes**: Create encrypted notes directly from the terminal

## Requirements

- Bash shell
- GnuPG (GPG) for encryption/decryption
- Optional: xclip/xsel (Linux) for clipboard operations

## Installation

1. Copy the `archangel.sh` script to your USB drive
2. Make it executable: `chmod +x archangel.sh`
3. Run it when you need to access your encrypted files: `./archangel.sh`

## Usage

1. Run the script from your USB drive
2. Enter your three encryption passphrases when prompted
3. Use the interactive menu to manage your encrypted files
4. When finished, end the session to ensure all files are encrypted

## Security Notes

- Passphrases are never stored or written to disk
- Files remain encrypted on the USB drive when not in use
- Be sure to use strong, unique passphrases for each encryption layer
- Only decrypt files when absolutely necessary

## Advanced Usage

### Clipboard Encryption

Securely transfer sensitive text by encrypting your clipboard:

1. Copy sensitive text to clipboard
2. Use the clipboard encryption option
3. Share the encrypted text
4. Recipient uses clipboard decryption to recover

### Panic Mode

For emergency situations where you need to quickly terminate the session:

1. Enable panic mode from the menu
2. Press 'p' at any time to instantly wipe the session

### Creating Encrypted Notes

Create notes directly from the terminal:

1. Select "Create encrypted note" option
2. Enter note title and content
3. Note will be encrypted and saved to USB

## License

MIT License
