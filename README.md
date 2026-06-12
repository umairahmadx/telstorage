# TelStorage

**Telegram as Ultimate Storage** — A Flutter mobile app that uses Telegram Bot API as a cloud storage backend with folder management, chunked uploads, and Google Sheets authentication.

## Features

- 📤 **Upload files** up to any size (automatically chunked into 45MB pieces)
- 📁 **Folder management** with hierarchical structure
- 🔐 **Secure authentication** via Google Sheets
- 📊 **Storage analytics** with category breakdown
- 🔍 **File browser** with folder navigation
- ⬇️ **Download files** with integrity verification (SHA-256)
- 🎨 **Modern UI** with Material Design 3
- 💾 **Local caching** with Hive for offline access

## Architecture

```
Flutter App (Mobile)
    ↓
Google Sheets (Authentication)
    ↓
Telegram Bot API (Cloud Storage)
    ↓
Private Telegram Channel (File Storage)
```

## Prerequisites

Before you begin, you'll need:
- Flutter SDK (3.5.0 or higher)
- A Google account
- A Telegram account
- Basic knowledge of Flutter development

## Setup Instructions

### 1. Telegram Bot Setup

1. Open Telegram and search for **@BotFather**
2. Send `/newbot` and follow the prompts
3. Copy the **bot token** (format: `123456:ABC-DEF1234ghIkl...`)
4. Create a **private Telegram channel** (this will store your files)
5. Add your bot as an **Administrator** with full permissions
6. Get the **channel ID**:
   - Send any message to the channel
   - Visit: `https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates`
   - Find `"chat":{"id":-1001234567890}` — copy this ID

### 2. Google Sheets Setup

1. Create a new Google Sheet
2. Rename the first tab to **users**
3. Add header row in row 1:
   ```
   email | password_hash | bot_token | channel_id
   ```
4. Go to **Extensions → Apps Script**
5. Delete any existing code
6. Copy the entire content from `google_apps_script/Code.gs` and paste it
7. Click **Deploy → New Deployment**
8. Select type: **Web app**
9. Settings:
   - Execute as: **Me**
   - Who has access: **Anyone**
10. Click **Deploy**
11. Copy the **Web App URL**

### 3. Environment Variable Configuration

To keep sensitive backend links and credentials secure and separate from source code, the project uses a `.env` configuration file loaded dynamically at startup:

1. Duplicate the `.env.example` file in the root directory and rename it to `.env`:
   ```bash
   cp .env.example .env
   ```
2. Open the new `.env` file and fill in your actual backend URLs:
   - `SCRIPT_URL`: Your deployed Google Apps Script Web App URL (from Step 2).
   - `WORKER_URL`: Your deployed Cloudflare Workers CORS Proxy URL (for Web download streams).

> [!NOTE]
> The `.env` file is registered in `.gitignore` so your private credentials and backend API endpoints are never checked into version control.

### 4. Install Dependencies & Build

Install the Dart packages (including the newly added `flutter_dotenv`) and compile code-generator files:

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

### 5. Run the App

Launch the application on Chrome (Web), Desktop, Android, or iOS:

```bash
flutter run
```

## Usage

### First Time Setup

1. Launch the app
2. Click **Register**
3. Enter:
   - Email
   - Password
   - Bot Token (from Telegram setup)
   - Channel ID (from Telegram setup)
4. The app will initialize your storage

### Login

Use your email and password to login on subsequent launches.

### Upload Files

1. Click the **Upload** button (FAB)
2. Select a file
3. Watch the progress
4. File appears in your browser

### Manage Files

- **Browse:** Navigate folders and files
- **Rename:** Long press → Rename
- **Move:** Long press → Move to folder
- **Delete:** Long press → Delete
- **Download:** Tap file to download and view

## Project Structure

```
lib/
├── main.dart                    # App entry, Hive init
├── app.dart                     # Root widget
├── core/
│   ├── constants/
│   │   └── app_constants.dart   # Configuration
│   ├── models/
│   │   ├── app_metadata.dart    # .metadata.json model
│   │   ├── file_record.dart     # Hive file model
│   │   ├── folder_record.dart   # Hive folder model
│   │   └── chunk_info.dart      # Chunk data model
│   ├── services/
│   │   ├── auth_service.dart    # Login/register
│   │   ├── telegram_service.dart # Telegram API
│   │   ├── metadata_service.dart # Metadata management
│   │   ├── hive_service.dart    # Local cache
│   │   ├── file_manager.dart    # File operations
│   │   ├── upload_service.dart  # Upload pipeline
│   │   └── download_service.dart # Download pipeline
│   ├── routing/
│   │   └── app_router.dart      # Navigation
│   └── theme/
│       └── app_theme.dart       # UI theme
├── features/
│   ├── auth/
│   │   └── screens/
│   │       ├── splash_screen.dart
│   │       ├── login_screen.dart
│   │       └── register_screen.dart
│   ├── home/
│   │   └── screens/
│   │       └── home_screen.dart  # Dashboard
│   └── browser/
│       ├── screens/
│       │   └── browser_screen.dart # File browser
│       └── widgets/
│           ├── file_tile.dart
│           └── folder_tile.dart
└── shared/
    └── widgets/
        └── storage_ring.dart    # Storage indicator
```

## How It Works

### Upload Pipeline

1. User picks a file
2. File is hashed (SHA-256) for integrity verification
3. File is split into 45MB chunks
4. Each chunk is uploaded to Telegram as a document
5. A metadata JSON file is created with chunk references
6. Global `.metadata.json` is updated with storage stats
7. Local Hive cache is updated for offline access

### Download Pipeline

1. User selects a file
2. File metadata JSON is fetched from Telegram
3. All chunks are downloaded in order
4. Chunks are reassembled
5. SHA-256 hash is verified
6. File is ready for viewing/saving

### Storage Structure on Telegram

```
📌 Pinned: .metadata.json          # Storage stats + folder tree
msg 5000: uuid-1234.json           # File metadata
msg 5001: uuid-1234_chunk_1        # File chunk 1
msg 5002: uuid-1234_chunk_2        # File chunk 2
...
```

## Technical Details

### Technologies Used

- **Flutter** - Cross-platform mobile framework
- **Hive** - Local NoSQL database for caching
- **Dio** - HTTP client for API calls
- **Telegram Bot API** - Cloud storage backend
- **Google Apps Script** - Authentication backend

### Storage Limits

- **Default quota:** 10 GB per user (configurable)
- **Max chunk size:** 45 MB (Telegram limit: 50 MB)
- **File size:** Unlimited (automatically chunked)
- **Rate limiting:** 500ms delay between uploads

### Security

- Passwords stored in Google Sheets (use strong passwords)
- Bot tokens stored securely on device (FlutterSecureStorage)
- Files stored in your private Telegram channel
- SHA-256 integrity verification on downloads
- No third-party servers involved

## Troubleshooting

### "Network error" on registration
- Check Google Apps Script URL in `app_constants.dart`
- Verify Apps Script is deployed with "Anyone" access

### "Failed to pin message"
- Ensure bot has admin permissions in the channel
- Check all permissions are granted to the bot

### "Chat not found"
- Verify channel ID starts with `-100`
- Ensure bot is added to the channel

### Build errors
```bash
flutter clean
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

## Pre-push Checklist

Before pushing code or opening a pull request, run the following checks to ensure clean formatting, zero linter warnings, and a successful build:

1. **Format all Dart files**:
   ```bash
   dart format .
   ```
2. **Run Static Analysis (Linter checks)**:
   ```bash
   flutter analyze
   ```
3. **Run Unit & Widget Tests**:
   ```bash
   flutter test
   ```
4. **Verify Android APK Build**:
   ```bash
   flutter build apk --release
   ```

## Contributing

Pull requests are welcome! For major changes, please open an issue first to discuss what you would like to change.

## License

MIT License - See LICENSE file for details

## Acknowledgments

- Built with Flutter and Telegram Bot API
- Inspired by the need for unlimited cloud storage
- Thanks to the open-source community

---

**Note:** This app is for personal use. Respect Telegram's Terms of Service and don't abuse the API.
