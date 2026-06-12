# Getting Started with TelStorage

## ✅ Your Setup is Complete!

Your TelStorage app is ready to run. Here's a quick reference guide.

## 🚀 Quick Start

### Run the App

```bash
flutter run
```

### Login Credentials

- **Email:** YOUR_EMAIL
- **Password:** YOUR_PASSWORD

## 📱 App Features

### Home Dashboard
- View storage usage (circular progress ring)
- See file categories (Images, Videos, Docs, Others)
- Quick access to recent files
- Upload button (FAB)

### File Browser
- Navigate folders
- View all files
- Long press for context menu (Rename, Move, Delete)
- Create new folders

### Upload Files
1. Tap the Upload button (bottom right)
2. Select a file from your device
3. Watch the upload progress
4. File appears in the browser

## 🔧 Configuration

### Your Current Setup

**Google Apps Script URL:**
```
https://script.google.com/macros/s/YOUR_SCRIPT_DEPLOYMENT_ID/exec
```

**Bot Token:**
```
YOUR_TELEGRAM_BOT_TOKEN
```

**Channel ID:**
```
YOUR_TELEGRAM_CHANNEL_ID
```

### Storage Limit

Default: 10 GB

To change, edit `lib/core/constants/app_constants.dart`:
```dart
static const double defaultStorageLimitMb = 10240.0; // 10 GB
```

## 📊 How It Works

### File Upload Process
```
Pick File → Hash (SHA-256) → Split into 45MB chunks 
→ Upload to Telegram → Create metadata 
→ Update storage stats → Cache locally
```

### File Download Process
```
Select File → Fetch metadata → Download chunks 
→ Reassemble → Verify hash → Ready to view
```

## 🐛 Common Issues

### App won't build
```bash
flutter clean
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

### Login fails
- Check internet connection
- Verify credentials in Google Sheet
- Ensure Google Apps Script is accessible

### Upload fails
- Check bot has admin permissions in channel
- Verify channel ID is correct
- Ensure file size is reasonable for first test

### "Failed to pin message"
- Bot needs admin permissions in the Telegram channel
- Go to channel → Administrators → Add bot with all permissions

## 📁 Project Structure

```
lib/
├── main.dart                    # App entry point
├── app.dart                     # Root widget
├── core/
│   ├── constants/              # Configuration
│   ├── models/                 # Data models
│   ├── services/               # Business logic
│   ├── routing/                # Navigation
│   └── theme/                  # UI styling
├── features/
│   ├── auth/                   # Login & Register
│   ├── home/                   # Dashboard
│   └── browser/                # File browser
└── shared/
    └── widgets/                # Reusable components
```

## 🔐 Security Notes

- Bot token is stored securely on device (FlutterSecureStorage)
- Files are in your private Telegram channel
- SHA-256 verification ensures file integrity
- No third-party servers involved

## 📚 Additional Resources

- **README.md** - Complete documentation
- **google_apps_script/Code.gs** - Backend authentication code
- **Flutter Docs** - https://docs.flutter.dev/
- **Telegram Bot API** - https://core.telegram.org/bots/api

## 🎯 Next Steps

1. Run the app: `flutter run`
2. Login with your credentials
3. Upload a test file (< 5 MB recommended)
4. Explore the features
5. Check your Telegram channel to see the uploaded files

## 💡 Tips

- Start with small files (< 5 MB) for testing
- Large files are automatically chunked
- Files are cached locally for faster browsing
- Use folders to organize your files
- Check storage stats on the home screen

---

**Enjoy your unlimited cloud storage!** 🚀
