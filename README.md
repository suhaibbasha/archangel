# 🔐 [ArchAngel] Advanced USB Session Manager

<p align="center">
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/Platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey" alt="Platform">
  <img src="https://img.shields.io/badge/Security-AES--256-green" alt="Security">
  <img src="https://img.shields.io/badge/Version-2.0-orange" alt="Version">
</p>

**[ArchAngel]** provides military-grade encryption for your sensitive files on USB drives, using a secure RAM-based session model that ensures your data is only decrypted when needed, and securely wiped when finished.

## ✨ Features

- **🔒 Triple-Layer Encryption**: Each file is encrypted with 3 layers of AES-256 encryption
- **🧠 RAM-Based Session**: Decrypted files only exist in RAM, never persisted to disk
- **🖥️ Cross-Platform**: Works seamlessly on macOS, Linux, and Windows
- **⚡ USB Ejection Detection**: Automatically wipes session if USB is removed
- **🗑️ Secure File Handling**: Shreds files properly when deleted, leaving no traces
- **📋 Clipboard Encryption**: Securely encrypt/decrypt clipboard contents for safe transfer
- **🚨 Panic Mode**: Emergency session termination with a single keypress
- **✅ File Integrity Verification**: SHA-256 checksums to verify file integrity
- **📝 Encrypted Notes**: Create encrypted notes directly from the terminal

## 📋 Requirements

```
✓ Bash shell
✓ GnuPG (GPG) for encryption/decryption
✓ Optional: xclip/xsel (Linux) for clipboard operations
```

## 🚀 Installation

1. Copy the `archangel.sh` script to your USB drive
2. Run it when you need to access your encrypted files:
   ```bash
   ./archangel.sh
   ```

## 🔧 Usage

1. Run the script from your USB drive
2. Enter your three encryption passphrases when prompted
3. Use the interactive menu to manage your encrypted files:
   ```
   ╔══════════════════════════ OPTIONS ══════════════════════════╗
   ║ 1. Open file manager           6. Decrypt a file            ║
   ║ 2. Preview encrypted file      7. Clipboard encrypt/decrypt ║
   ║ 3. Encrypt all files now       8. Create encrypted note     ║
   ║ 4. Change session timeout      9. Toggle panic mode         ║
   ║ 5. Show session status         0. End session               ║
   ╚═════════════════════════════════════════════════════════════╝
   ```
4. When finished, end the session to ensure all files are encrypted

## 🔐 Security Notes

- **Zero Storage**: Passphrases are never stored or written to disk
- **Always Encrypted**: Files remain encrypted on the USB drive when not in use
- **Strong Passphrases**: Be sure to use strong, unique passphrases for each encryption layer
- **Minimal Exposure**: Only decrypt files when absolutely necessary

## 🛠️ Advanced Usage

### 📋 Clipboard Encryption

Securely transfer sensitive text by encrypting your clipboard:

1. Copy sensitive text to clipboard
2. Use the clipboard encryption option
3. Share the encrypted text (base64-encoded)
4. Recipient uses clipboard decryption to recover

### 🚨 Panic Mode

For emergency situations where you need to quickly terminate the session:

1. Enable panic mode from the menu
2. Press 'p' at any time to instantly wipe the session
3. All decrypted data is securely erased from memory

### 📝 Creating Encrypted Notes

Create notes directly from the terminal:

1. Select "Create encrypted note" option
2. Enter note title and content
3. Note will be encrypted and saved to USB automatically

## 📚 FAQ

**Q: Is my data safe if my USB is stolen?**

A: Yes, all files are triple-encrypted with AES-256 and require three different passphrases to decrypt.

**Q: What happens if I disconnect my USB while the session is active?**

A: [ArchAngel] will automatically detect the removal and securely wipe all decrypted files from RAM.

**Q: How secure is the clipboard encryption?**

A: Clipboard content is encrypted with the same triple-layer AES-256 encryption as files.

**Q: Can I use [ArchAngel] on non-USB storage?**

A: Yes, [Archangel] works on any storage medium, but is specifically designed for USB drives.
